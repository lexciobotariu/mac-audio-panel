import AppKit
import SwiftUI

/// MenuBarExtra windows grow with their content but never shrink, so removing
/// a card (onboarding, an error) leaves an empty, see-through strip. This keeps
/// the hosting window's height equal to the content's, pinned to its top edge
/// so the panel stays attached to the menu bar.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WindowHeightSetter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        DispatchQueue.main.async {
            guard height > 0, let window = view.window else { return }
            let target = window.frameRect(
                forContentRect: NSRect(x: 0, y: 0, width: window.frame.width, height: height)
            ).height
            var frame = window.frame
            guard abs(frame.height - target) > 0.5 else { return }
            frame.origin.y += frame.height - target   // keep the top edge fixed
            frame.size.height = target
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

extension View {
    /// Resizes the enclosing window to fit this view's height, both ways.
    func syncWindowHeight() -> some View {
        modifier(SyncWindowHeight())
    }
}

private struct SyncWindowHeight: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(ContentHeightKey.self) { height = $0 }
            .background(WindowHeightSetter(height: height))
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
