import SwiftUI

/// App icon mark used in vault manager, help, and export branding.
struct DreftAppMark: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        Image("DreftAppMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Backward-compatible alias while older call sites migrate.
typealias DreftGemLogo = DreftAppMark
