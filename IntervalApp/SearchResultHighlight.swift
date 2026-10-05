#if !os(watchOS)
import SwiftUI

enum SearchResultHighlightTiming {
    static let fadeDuration: TimeInterval = 2.6
    static let activeDuration: TimeInterval = 3.0
}

struct SearchResultHighlight: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var intensity: Double = 0

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(intensity))
                    .shadow(color: Color.primary.opacity(intensity * 1.5), radius: 12)
                    .allowsHitTesting(false)
            }
            .onAppear {
                if isActive { playFade() }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    playFade()
                } else {
                    intensity = 0
                }
            }
    }

    private func playFade() {
        intensity = colorScheme == .dark ? 0.12 : 0.075
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: SearchResultHighlightTiming.fadeDuration)) {
                intensity = 0
            }
        }
    }
}

extension View {
    func searchResultHighlight(_ isActive: Bool) -> some View {
        modifier(SearchResultHighlight(isActive: isActive))
    }
}
#endif
