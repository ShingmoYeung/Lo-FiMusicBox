import AppKit
import SwiftUI

private struct InteractiveCursorModifier: ViewModifier {
    var cursor: NSCursor

    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                updateCursor(isHovering: isHovering)
            }
            .onDisappear {
                updateCursor(isHovering: false)
            }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering && !isCursorActive {
            cursor.push()
            isCursorActive = true
        } else if !isHovering && isCursorActive {
            NSCursor.pop()
            isCursorActive = false
        }
    }
}

extension View {
    /// Use for clickable custom controls that do not get a reliable pointing-hand cursor from AppKit.
    func pointingHandCursor() -> some View {
        modifier(InteractiveCursorModifier(cursor: .pointingHand))
    }
}
