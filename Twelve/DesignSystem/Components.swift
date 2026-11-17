import SwiftUI
import TwelveCore

// Reusable building blocks. Paper surfaces carry content; Liquid Glass is
// reserved for controls that float above it.

/// A cream reading surface with a hairline edge.
struct PaperCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
            .shadow(color: Color.ocean.opacity(0.1), radius: 14, y: 6)
    }
}

/// The dark espresso surface used for the most important thing on a screen.
struct FeatureCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            // White text and light controls on the bright sky.
            .environment(\.colorScheme, .dark)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SkyBackground(style: .vivid, clouds: 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            }
            .shadow(color: Color.ocean.opacity(0.3), radius: 18, y: 10)
    }
}

/// Cards lift slightly under a finger.
struct LiftButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// An animated circular progress indicator.
struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 8
    var tint: Color = .lime
    var track: Color = Color.white.opacity(0.3)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.85), value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// A slim linear progress bar.
struct ProgressBar: View {
    var fraction: Double
    var tint: Color = .pop
    var track: Color = .hairline
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// The main call to action: a prominent glass button.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    /// Lime by default, with dark text; any other tint gets white text.
    var tint: Color = .lime
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy))
                if let systemImage { Image(systemName: systemImage).font(.subheadline.weight(.bold)) }
            }
            .foregroundStyle(tint == .lime ? Color.night : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(tint)
    }
}

/// A quieter glass button for secondary actions.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// Small tracked capitals above a section.
struct SectionLabel: View {
    let text: String
    var color: Color = .inkSoft
    init(_ text: String, color: Color = .inkSoft) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text).capsLabel(color).accessibilityAddTraits(.isHeader)
    }
}

/// A number that rolls when it changes.
struct RollingNumber: View {
    let text: String
    var font: Font
    var color: Color = .ink
    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(.snappy, value: text)
    }
}

/// A pill-shaped tag.
struct Tag: View {
    let text: String
    var systemImage: String?
    var tint: Color = .accentText
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

/// A calm empty state.
struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Color.inkSoft)
            Text(title).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
            Text(message).font(.subheadline).foregroundStyle(Color.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

/// A banner for offline / informational states.
struct InfoBanner: View {
    let symbol: String
    let text: String
    var tint: Color = .mintText
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.footnote).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Standard screen scaffold: paper background and comfortable margins.
    func paperScreen() -> some View {
        self.background(PaperBackground())
    }

    /// A page-turn style transition between months; a simple fade when
    /// Reduce Motion is on.
    func pageTurn(forward: Bool, reduceMotion: Bool) -> some View {
        self.transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
    }
}

/// A local photo thumbnail that loads off the main thread's critical path.
struct LocalPhoto: View {
    let file: String?
    var body: some View {
        if let image = PhotoStore.image(file) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.hairline.opacity(0.5)
                Image(systemName: "photo").foregroundStyle(Color.inkSoft)
            }
        }
    }
}

/// Wraps the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
