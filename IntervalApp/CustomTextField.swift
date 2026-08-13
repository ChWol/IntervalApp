import SwiftUI

#if os(macOS)
import AppKit

class NoHighlightTextField: NSTextField {
    var pendingFocus: Bool = false

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && pendingFocus {
            pendingFocus = false
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
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

        c.onFocusChanged = onFocusChanged
        c.onSubmit = onSubmit
        c.onDeleteEmpty = onDeleteEmpty

        if c.isEditing {
            return
        }

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isFocused && nsView.currentEditor() == nil {
            if nsView.window != nil {
                DispatchQueue.main.async {
                    if nsView.currentEditor() == nil {
                        nsView.window?.makeFirstResponder(nsView)
                    }
                }
            } else {
                nsView.pendingFocus = true
            }
        } else if !isFocused {
            nsView.pendingFocus = false
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
#else
import UIKit

struct CustomTextField: View {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChanged: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void
    var fontSize: CGFloat
    var placeholder: String
    
    @FocusState private var fieldFocused: Bool
    
    var body: some View {
        let active = isFocused || fieldFocused
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.system(size: fontSize, weight: .light))
            .lineLimit(active ? nil : 1)
            .fixedSize(horizontal: false, vertical: active)
            .focused($fieldFocused)
            .onSubmit {
                onSubmit()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        fieldFocused = false
                        onFocusChanged(false)
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: isFocused) { _, newValue in
                fieldFocused = newValue
            }
            .onChange(of: fieldFocused) { _, newValue in
                onFocusChanged(newValue)
            }
            .onAppear {
                if isFocused {
                    fieldFocused = true
                }
            }
    }
}
#endif
