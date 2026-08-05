import SwiftUI
import AppKit

class NoHighlightTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        return result
    }
}

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChanged: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void
    var fontSize: CGFloat
    var placeholder: String

    func makeNSView(context: Context) -> NoHighlightTextField {
        let tf = NoHighlightTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: fontSize, weight: .light)
        tf.placeholderString = placeholder
        tf.delegate = context.coordinator
        tf.cell?.focusRingType = .none
        tf.stringValue = text
        return tf
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NoHighlightTextField, context: Context) -> CGSize? {
        let s = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? s.width, height: s.height)
    }

    func updateNSView(_ nsView: NoHighlightTextField, context: Context) {
        let c = context.coordinator

        // Always keep callbacks fresh so closures capture latest state
        c.onFocusChanged = onFocusChanged
        c.onSubmit = onSubmit
        c.onDeleteEmpty = onDeleteEmpty

        // While the user is actively typing, do NOT touch the NSTextField at all.
        // Setting stringValue or calling makeFirstResponder while AppKit's field
        // editor is active destroys the editing session and produces a beep.
        if c.isEditing {
            return
        }

        // Sync text only when not editing
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Acquire focus only if we don't already have it
        if isFocused && nsView.currentEditor() == nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(textBinding: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>
        var onFocusChanged: ((Bool) -> Void)?
        var onSubmit: (() -> Void)?
        var onDeleteEmpty: (() -> Void)?
        var isEditing: Bool = false

        init(textBinding: Binding<String>) {
            self.textBinding = textBinding
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            textBinding.wrappedValue = tf.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            onFocusChanged?(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            // Final sync of text on editing end as safety net
            if let tf = obj.object as? NSTextField {
                textBinding.wrappedValue = tf.stringValue
            }
            onFocusChanged?(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            if sel == #selector(NSResponder.deleteBackward(_:)) {
                if textBinding.wrappedValue.isEmpty {
                    onDeleteEmpty?()
                    return true
                }
            }
            return false
        }
    }
}
