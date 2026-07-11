import CoreGraphics
import Foundation
import ImageIO

/// Decodes display-sized thumbnails once per card. Full image data lives on disk in the vault.
final class CanvasImageCache {
  static let shared = CanvasImageCache()
  static let displayMaxPixelEdge = 1024

  private let cache = NSCache<NSString, CGImage>()

  private init() {
    cache.countLimit = 96
    cache.totalCostLimit = 128 * 1024 * 1024
  }

  /// Synchronous lookup — reads from vault file or legacy base64 content.
  func displayImage(forCardID id: String, content: String, vaultURL: URL?) -> CGImage? {
    let cacheKey = "\(id)|\(content.hashValue)" as NSString
    if let cached = cache.object(forKey: cacheKey) { return cached }

    let data: Data?
    if VaultFilesystem.isEmbeddedImageContent(content) {
      data = Data(base64Encoded: content, options: .ignoreUnknownCharacters)
    } else if let vaultURL {
      data = VaultFilesystem.imageData(at: content, vaultURL: vaultURL)
    } else {
      data = nil
    }

    guard let data, let image = Self.decodeThumbnail(from: data) else { return nil }

    let cost = image.bytesPerRow * image.height
    cache.setObject(image, forKey: cacheKey, cost: cost)
    return image
  }

  /// Prefetch thumbnail off the main thread during import.
  func prepareDisplayImage(data: Data, cardID: String, contentKey: String) async {
    let key = "\(cardID)|\(contentKey.hashValue)" as NSString
    if cache.object(forKey: key) != nil { return }

    let payload = data
    let image = await Task.detached(priority: .userInitiated) {
      Self.decodeThumbnail(from: payload)
    }.value
    guard let image else { return }

    let cost = image.bytesPerRow * image.height
    cache.setObject(image, forKey: key, cost: cost)
  }

  func remove(cardID: String) {
    // Keys include content hash; clearing all keys for this card id prefix is enough on delete.
    cache.removeObject(forKey: cardID as NSString)
  }

  private static func decodeThumbnail(from data: Data) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false,
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: displayMaxPixelEdge,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return image
  }
}
