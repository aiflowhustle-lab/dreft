import CoreGraphics
import Foundation
import ImageIO

/// Decodes display-sized thumbnails once per card. Full image data lives on disk in the vault.
final class CanvasImageCache {
  static let shared = CanvasImageCache()
  static let displayMaxPixelEdge = 1024

  private let lru = LRUImageCache(
    maxEntries: CanvasConstants.imageCacheMaxEntries,
    maxTotalCost: CanvasConstants.imageCacheMaxBytes
  )
  private let loadCoordinator = LoadCoordinator()

  private init() {}

  static func keyString(forCardID id: String, content: String) -> String {
    "\(id)|\(content.hashValue)"
  }

  /// Marks thumbnails that should not be evicted while still on screen (strict viewport).
  func setPinnedKeys(_ keys: Set<String>) {
    lru.setPinnedKeys(keys)
  }

  /// Cache lookup only — never blocks on disk or decode.
  func cachedImage(forCardID id: String, content: String) -> CGImage? {
    lru.image(forKey: Self.keyString(forCardID: id, content: content))
  }

  /// Synchronous lookup — reads from vault file or legacy base64 content.
  func displayImage(forCardID id: String, content: String, vaultURL: URL?) -> CGImage? {
    let key = Self.keyString(forCardID: id, content: content)
    if let cached = lru.image(forKey: key) { return cached }
    guard let image = loadImage(forCardID: id, content: content, vaultURL: vaultURL) else { return nil }
    lru.insert(key: key, image: image, cost: imageCost(image))
    return image
  }

  /// Decode off the main thread; calls `onComplete` on the main actor when a new image is cached.
  func scheduleDisplayImage(
    forCardID id: String,
    content: String,
    vaultURL: URL?,
    onComplete: @escaping @MainActor () -> Void
  ) {
    let keyString = Self.keyString(forCardID: id, content: content)
    if cachedImage(forCardID: id, content: content) != nil {
      Task { @MainActor in onComplete() }
      return
    }

    Task {
      guard await loadCoordinator.tryStart(keyString) else { return }
      let loaded = await Task.detached(priority: .userInitiated) { [weak self] in
        self?.storeImage(forCardID: id, content: content, vaultURL: vaultURL) ?? false
      }.value
      await loadCoordinator.finish(keyString)
      if loaded {
        await MainActor.run { onComplete() }
      }
    }
  }

  /// Prefetch thumbnail off the main thread during import or viewport prefetch.
  func prepareDisplayImage(data: Data, cardID: String, contentKey: String) async {
    let key = Self.keyString(forCardID: cardID, content: contentKey)
    if lru.image(forKey: key) != nil { return }

    let payload = data
    let image = await Task.detached(priority: .userInitiated) {
      Self.decodeThumbnail(from: payload)
    }.value
    guard let image else { return }
    lru.insert(key: key, image: image, cost: imageCost(image))
  }

  /// Prefetch from vault path when card enters the viewport.
  func prepareDisplayImageIfNeeded(forCardID id: String, content: String, vaultURL: URL?) async -> Bool {
    let key = Self.keyString(forCardID: id, content: content)
    if lru.image(forKey: key) != nil { return false }
    return await Task.detached(priority: .utility) { [weak self] in
      self?.storeImage(forCardID: id, content: content, vaultURL: vaultURL) ?? false
    }.value
  }

  func remove(cardID: String) {
    lru.removeKeys(withPrefix: "\(cardID)|")
  }

  @discardableResult
  private func storeImage(forCardID id: String, content: String, vaultURL: URL?) -> Bool {
    let key = Self.keyString(forCardID: id, content: content)
    if lru.image(forKey: key) != nil { return false }
    guard let image = loadImage(forCardID: id, content: content, vaultURL: vaultURL) else { return false }
    lru.insert(key: key, image: image, cost: imageCost(image))
    return true
  }

  private func imageCost(_ image: CGImage) -> Int {
    image.bytesPerRow * image.height
  }

  private func loadImage(forCardID id: String, content: String, vaultURL: URL?) -> CGImage? {
    let data: Data?
    if VaultFilesystem.isEmbeddedImageContent(content) {
      data = Data(base64Encoded: content, options: .ignoreUnknownCharacters)
    } else if let vaultURL {
      data = VaultFilesystem.imageData(at: content, vaultURL: vaultURL)
    } else {
      data = nil
    }
    guard let data else { return nil }
    return Self.decodeThumbnail(from: data)
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

// MARK: - LRU backing store

private final class LRUImageCache {
  private struct Entry {
    let image: CGImage
    let cost: Int
  }

  private let maxEntries: Int
  private let maxTotalCost: Int
  private var entries: [String: Entry] = [:]
  private var lruOrder: [String] = []
  private var totalCost = 0
  private var pinnedKeys = Set<String>()
  private let lock = NSLock()

  init(maxEntries: Int, maxTotalCost: Int) {
    self.maxEntries = maxEntries
    self.maxTotalCost = maxTotalCost
  }

  func setPinnedKeys(_ keys: Set<String>) {
    lock.lock()
    pinnedKeys = keys
    lock.unlock()
  }

  func image(forKey key: String) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    guard let entry = entries[key] else { return nil }
    touchLocked(key)
    return entry.image
  }

  func insert(key: String, image: CGImage, cost: Int) {
    lock.lock()
    defer { lock.unlock() }
    if let existing = entries[key] {
      totalCost -= existing.cost
      lruOrder.removeAll { $0 == key }
    }
    entries[key] = Entry(image: image, cost: cost)
    lruOrder.append(key)
    totalCost += cost
    trimLocked()
  }

  func removeKeys(withPrefix prefix: String) {
    lock.lock()
    defer { lock.unlock() }
    let victims = entries.keys.filter { $0.hasPrefix(prefix) }
    for key in victims {
      removeLocked(key)
    }
  }

  private func touchLocked(_ key: String) {
    lruOrder.removeAll { $0 == key }
    lruOrder.append(key)
  }

  private func trimLocked() {
    while totalCost > maxTotalCost || lruOrder.count > maxEntries {
      guard let victim = lruOrder.first(where: { !pinnedKeys.contains($0) }) else { break }
      removeLocked(victim)
    }
  }

  private func removeLocked(_ key: String) {
    guard let entry = entries.removeValue(forKey: key) else { return }
    totalCost -= entry.cost
    lruOrder.removeAll { $0 == key }
    pinnedKeys.remove(key)
  }
}

private actor LoadCoordinator {
  private var inFlight = Set<String>()

  func tryStart(_ key: String) -> Bool {
    if inFlight.contains(key) { return false }
    inFlight.insert(key)
    return true
  }

  func finish(_ key: String) {
    inFlight.remove(key)
  }
}
