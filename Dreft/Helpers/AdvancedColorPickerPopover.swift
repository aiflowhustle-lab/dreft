import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AdvancedColorPickerPopover: View {
    @Binding var color: Color

    @State private var hue: Double = 0
    @State private var saturation: Double = 0.8
    @State private var brightness: Double = 0.9

    var body: some View {
        VStack(spacing: 12) {
            saturationBrightnessArea

            HStack(spacing: 12) {
                eyedropperButton

                Circle()
                    .fill(currentColor)
                    .frame(width: 34, height: 34)

                hueSlider
            }

            rgbFields
        }
        .padding(14)
        .frame(width: 250)
        .onAppear {
            syncFromColor()
        }
    }

    private var currentColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func commit() {
        color = currentColor
    }

    private func syncFromColor() {
        #if os(macOS)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        #else
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        #endif
    }

    private var saturationBrightnessArea: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .fill(currentColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(
                        x: saturation * geo.size.width,
                        y: (1 - brightness) * geo.size.height
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(value.location.x / geo.size.width, 0), 1)
                        brightness = 1 - min(max(value.location.y / geo.size.height, 0), 1)
                        commit()
                    }
            )
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var eyedropperButton: some View {
        Button {
            #if os(macOS)
            NSColorSampler().show { picked in
                guard let picked, let srgb = picked.usingColorSpace(.sRGB) else { return }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                hue = h
                saturation = s
                brightness = b
                commit()
            }
            #endif
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 15))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Pick color from screen")
    }

    private var hueSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: (0...6).map {
                        Color(hue: Double($0) / 6, saturation: 1, brightness: 1)
                    },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(Capsule())

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: hue * (geo.size.width - 14))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / geo.size.width, 0), 1)
                        commit()
                    }
            )
        }
        .frame(height: 14)
    }

    private var rgbComponents: (r: Int, g: Int, b: Int) {
        #if os(macOS)
        let ns = NSColor(currentColor).usingColorSpace(.sRGB) ?? .black
        return (Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(currentColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255))
        #endif
    }

    private func setRGB(r: Int, g: Int, b: Int) {
        #if os(macOS)
        let ns = NSColor(
            srgbRed: CGFloat(min(max(r, 0), 255)) / 255,
            green: CGFloat(min(max(g, 0), 255)) / 255,
            blue: CGFloat(min(max(b, 0), 255)) / 255,
            alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        hue = h
        saturation = s
        brightness = br
        commit()
        #else
        let ui = UIColor(
            red: CGFloat(min(max(r, 0), 255)) / 255,
            green: CGFloat(min(max(g, 0), 255)) / 255,
            blue: CGFloat(min(max(b, 0), 255)) / 255,
            alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        hue = h
        saturation = s
        brightness = br
        commit()
        #endif
    }

    private var rgbFields: some View {
        let rgb = rgbComponents
        return HStack(spacing: 10) {
            rgbField(label: "R", value: rgb.r) { setRGB(r: $0, g: rgb.g, b: rgb.b) }
            rgbField(label: "G", value: rgb.g) { setRGB(r: rgb.r, g: $0, b: rgb.b) }
            rgbField(label: "B", value: rgb.b) { setRGB(r: rgb.r, g: rgb.g, b: $0) }
        }
    }

    private func rgbField(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 4) {
            TextField(
                "",
                text: Binding(
                    get: { String(value) },
                    set: { if let intValue = Int($0) { onChange(intValue) } }
                )
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}
