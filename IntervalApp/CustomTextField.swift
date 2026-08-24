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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v" {
            if let str = NSPasteboard.general.string(forType: .string) {
                let rawLines = str.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if rawLines.count > 1 {
                    if let coord = delegate as? CustomTextField.Coordinator {
                        coord.onPasteMultipleLines?(rawLines)
                        return true
                    }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
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
        let isRTL = LocalizationManager.shared.currentLanguage == .arabic
        tf.alignment = isRTL ? .right : .left
        tf.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        if isFocused {
            tf.pendingFocus = true
        }
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

        let isRTL = LocalizationManager.shared.currentLanguage == .arabic
        let targetAlignment: NSTextAlignment = isRTL ? .right : .left
        if nsView.alignment != targetAlignment {
            nsView.alignment = targetAlignment
            nsView.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
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
            NotificationCenter.default.post(name: .taskTextDidGrow, object: nil)
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
                let isAtBeginning = textView.selectedRange().location == 0
                onSubmit?(isAtBeginning)
                return true
            }
            if sel == #selector(NSResponder.deleteBackward(_:)) {
                if textBinding.wrappedValue.isEmpty || textView.string.isEmpty {
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

struct CustomTextField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChanged: (Bool) -> Void
    var onSubmit: (_ isAtBeginning: Bool) -> Void
    var onDeleteEmpty: () -> Void
    var onPasteMultipleLines: (([String]) -> Void)? = nil
    var fontSize: CGFloat
    var placeholder: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: fontSize, weight: .light)
        tv.textColor = .label
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.delegate = context.coordinator
        tv.returnKeyType = .default
        tv.autocorrectionType = .yes
        tv.spellCheckingType = .yes
        tv.text = text
        
        let isRTL = LocalizationManager.shared.currentLanguage == .arabic
        tv.textAlignment = isRTL ? .right : .left
        
        // Accessory bar to dismiss keyboard
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneBtn = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.dismissKeyboard)
        )
        doneBtn.tintColor = .secondaryLabel
        toolbar.items = [flex, doneBtn]
        toolbar.sizeToFit()
        tv.inputAccessoryView = toolbar
        
        if isFocused {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
            }
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let c = context.coordinator
        c.onFocusChanged = onFocusChanged
        c.onSubmit = onSubmit
        c.onDeleteEmpty = onDeleteEmpty
        c.onPasteMultipleLines = onPasteMultipleLines
        c.textView = uiView

        if c.isEditing { return }

        if uiView.text != text {
            uiView.text = text
        }
        
        uiView.font = .systemFont(ofSize: fontSize, weight: .light)
        let isRTL = LocalizationManager.shared.currentLanguage == .arabic
        uiView.textAlignment = isRTL ? .right : .left

        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? uiView.bounds.width
        let width = w > 0 ? w : (UIScreen.main.bounds.width - 80)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, fontSize * 1.2))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(textBinding: $text)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var textBinding: Binding<String>
        var onFocusChanged: ((Bool) -> Void)?
        var onSubmit: ((_ isAtBeginning: Bool) -> Void)?
        var onDeleteEmpty: (() -> Void)?
        var onPasteMultipleLines: (([String]) -> Void)?
        var isEditing: Bool = false
        weak var textView: UITextView?

        init(textBinding: Binding<String>) {
            self.textBinding = textBinding
        }

        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        func textViewDidChange(_ textView: UITextView) {
            textBinding.wrappedValue = textView.text
            textView.scrollRangeToVisible(textView.selectedRange)
            NotificationCenter.default.post(name: .taskTextDidGrow, object: nil)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            onFocusChanged?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            textBinding.wrappedValue = textView.text
            onFocusChanged?(false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Enter key pressed -> Submit new item
            if text == "\n" {
                let isAtBeginning = range.location == 0
                onSubmit?(isAtBeginning)
                return false
            }
            
            // Backspace on empty text
            if text.isEmpty && range.length == 0 && textView.text.isEmpty {
                onDeleteEmpty?()
                return false
            }
            
            // Multiple lines pasted
            if text.contains("\n") || text.contains("\r") {
                let rawLines = text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if rawLines.count > 1 {
                    onPasteMultipleLines?(rawLines)
                    return false
                }
            }
            
            return true
        }
    }
}
#endif
