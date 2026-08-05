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

    func makeNSView(context: Context) -> NSTextField {
        let textField = NoHighlightTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: fontSize, weight: .light)
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.cell?.focusRingType = .none
        return textField
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = .systemFont(ofSize: fontSize, weight: .light)
        
        let currentlyFocused = (nsView.window?.firstResponder == nsView.currentEditor() && nsView.currentEditor() != nil)
        
        if isFocused && !currentlyFocused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !isFocused && currentlyFocused {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextField

        init(_ parent: CustomTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChanged(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onFocusChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if parent.text.isEmpty {
                    parent.onDeleteEmpty()
                    return true
                }
            }
            return false
        }
    }
}
