import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppVisualTokens {
    static func modalScrim(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.78)
    }
}

/// Consistent feedback for the app's deliberately minimal buttons. Labels retain their
/// existing visual design while mouse hover, keyboard/touch press, and disabled state are
/// always perceptible.
struct InteractivePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonBody(configuration: configuration)
    }

    private struct InteractiveButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(!isEnabled ? 0.42 : configuration.isPressed ? 0.62 : isHovering ? 0.84 : 1)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                #if os(macOS)
                .onHover { hovering in
                    isHovering = hovering
                    (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
                }
                #elseif os(iOS)
                .hoverEffect(.highlight)
                #endif
        }
    }
}
