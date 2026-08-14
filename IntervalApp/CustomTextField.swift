import SwiftUI

#if os(macOS)
import AppKit

class NoHighlightTextField: NSTextField {
    var pendingFocus: Bool = false

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.delegate = delegate as? NSTextViewDelegate
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
    var onSubmit: (_ isAtBeginning: Bool) -> Void
    var onDeleteEmpty: () -> Void
    var onPasteMultipleLines: (([String]) -> Void)? = nil
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
        tf.usesSingleLineMode = false
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.stringValue = text
        return tf
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NoHighlightTextField, context: Context) -> CGSize? {
        let w = proposal.width ?? nsView.bounds.width
        let intrinsic = nsView.intrinsicContentSize
        let string = nsView.stringValue
        if string.isEmpty || !string.contains("\n") {
            let font = nsView.font ?? .systemFont(ofSize: fontSize, weight: .light)
            let fontLineHeight = font.ascender - font.descender + font.leading
            let rect = (string as NSString).boundingRect(
                with: CGSize(width: w > 0 ? w : 1000, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            if ceil(rect.height) <= fontLineHeight * 1.3 {
                return CGSize(width: w > 0 ? w : intrinsic.width, height: intrinsic.height)
            }
        }
        let font = nsView.font ?? .systemFont(ofSize: fontSize, weight: .light)
        let rect = (string as NSString).boundingRect(
            with: CGSize(width: w > 0 ? w : 1000, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let h = max(intrinsic.height, ceil(rect.height))
        return CGSize(width: w > 0 ? w : intrinsic.width, height: h)
    }

    func updateNSView(_ nsView: NoHighlightTextField, context: Context) {
        let c = context.coordinator

        c.onFocusChanged = onFocusChanged
        c.onSubmit = onSubmit
        c.onDeleteEmpty = onDeleteEmpty
        c.onPasteMultipleLines = onPasteMultipleLines

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

    class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var textBinding: Binding<String>
        var onFocusChanged: ((Bool) -> Void)?
        var onSubmit: ((_ isAtBeginning: Bool) -> Void)?
        var onDeleteEmpty: (() -> Void)?
        var onPasteMultipleLines: (([String]) -> Void)?
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
            if let tf = obj.object as? NSTextField, let tv = tf.currentEditor() as? NSTextView {
                tv.delegate = self
            }
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
                let isAtBeginning = textView.selectedRange().location == 0
                onSubmit?(isAtBeginning)
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

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let str = replacementString, let onPaste = onPasteMultipleLines else { return true }
            if str.contains("\n") || str.contains("\r") {
                let rawLines = str.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if rawLines.count > 1 {
                    let currentStr = (textView.string as NSString)
                    let prefix = affectedCharRange.location <= currentStr.length ? currentStr.substring(to: affectedCharRange.location) : ""
                    let suffix = (affectedCharRange.location + affectedCharRange.length) <= currentStr.length ? currentStr.substring(from: affectedCharRange.location + affectedCharRange.length) : ""
                    var allLinesToInsert = rawLines
                    allLinesToInsert[0] = prefix + rawLines[0] + suffix
                    onPaste(allLinesToInsert)
                    return false
                }
            }
            return true
        }
    }
}
#else
import UIKit

struct CustomTextField: View {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChanged: (Bool) -> Void
    var onSubmit: (_ isAtBeginning: Bool) -> Void
    var onDeleteEmpty: () -> Void
    var onPasteMultipleLines: (([String]) -> Void)? = nil
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
                onSubmit(text.isEmpty)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        fieldFocused = false
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: text) { _, newText in
                if newText.contains("\n") || newText.contains("\r") {
                    let rawLines = newText.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if rawLines.count > 1, let onPaste = onPasteMultipleLines {
                        onPaste(rawLines)
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
