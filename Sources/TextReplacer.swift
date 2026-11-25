import ApplicationServices
import Cocoa

final class TextReplacer {
    static let shared = TextReplacer()
    static let syntheticEventTag: Int64 = 0x4D595357 // "MYSW"

    private enum SelectionState {
        case selected
        case empty
        case unknown
    }

    private let workQueue = DispatchQueue(label: "com.myswitcher.replacer", qos: .userInteractive)

    private init() {}

    func convertSelectionOrLastWord(recentTypedWord: String = "") {
        workQueue.async {
            let currentScript = InputSourceManager.shared.currentScript()
            let selectionState = self.detectSelectionViaAX()
            let savedPasteboard = self.snapshotPasteboard()

            var copiedText: String?
            var didAutoSelectWord = false
            var deleteCountForReplacement: Int?

            switch selectionState {
            case .selected:
                copiedText = self.copyCurrentSelection()

            case .empty:
                if let axToken = self.readTokenBeforeCaretViaAX(), !axToken.isEmpty {
                    copiedText = axToken
                    deleteCountForReplacement = axToken.count
                } else if !recentTypedWord.isEmpty {
                    copiedText = recentTypedWord
                    deleteCountForReplacement = recentTypedWord.count
                } else {
                    didAutoSelectWord = true
                    self.selectWordToLeft()
                    copiedText = self.copyCurrentSelection()
                }

            case .unknown:
                // AX doesn't expose selection in this app: try Cmd+C first so we never
                // accidentally extend an existing selection with Option+Shift+Left.
                copiedText = self.copyCurrentSelection()
                if copiedText == nil || copiedText?.isEmpty == true {
                    if !recentTypedWord.isEmpty {
                        copiedText = recentTypedWord
                        deleteCountForReplacement = recentTypedWord.count
                    } else {
                        didAutoSelectWord = true
                        self.selectWordToLeft()
                        copiedText = self.copyCurrentSelection()
                    }
                }
            }

            guard let original = copiedText, !original.isEmpty else {
                if didAutoSelectWord {
                    self.sendKeyCombo(keyCode: 124, flags: []) // Right arrow to clear selection
                }
                self.restorePasteboard(savedPasteboard)
                return
            }

            let result = TextConverter.convert(original, currentScript: currentScript)

            if let count = deleteCountForReplacement {
                for _ in 0..<count {
                    self.sendKeyCombo(keyCode: 51, flags: []) // Backspace
                    usleep(4_000)
                }
                usleep(15_000)
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(result.text, forType: .string)
            usleep(20_000)
            self.sendKeyCombo(keyCode: 9, flags: [.maskCommand]) // 'v'

            DispatchQueue.main.async {
                InputSourceManager.shared.switchToScript(result.targetScript)
            }

            usleep(120_000)
            self.restorePasteboard(savedPasteboard)
        }
    }

    func autoReplaceWordBeforeSpace(originalLength: Int, replacement: String, targetScript: LayoutScript) {
        workQueue.async {
            // Wait briefly for the Space key event to be processed by the target app
            usleep(35_000)

            let savedPasteboard = self.snapshotPasteboard()

            // Step left past the space
            self.sendKeyCombo(keyCode: 123, flags: []) // Left arrow
            usleep(15_000)

            // Delete the exact number of characters typed for this word
            for _ in 0..<originalLength {
                self.sendKeyCombo(keyCode: 51, flags: []) // Backspace
                usleep(4_000)
            }
            usleep(15_000)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(replacement, forType: .string)
            usleep(20_000)
            self.sendKeyCombo(keyCode: 9, flags: [.maskCommand]) // Cmd+V
            usleep(30_000)

            // Step right past the space
            self.sendKeyCombo(keyCode: 124, flags: []) // Right arrow

            DispatchQueue.main.async {
                InputSourceManager.shared.switchToScript(targetScript)
            }

            usleep(120_000)
            self.restorePasteboard(savedPasteboard)
        }
    }

    func isFocusedElementSecureTextField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObj) == .success,
              let focused = focusedObj else {
            return false
        }
        let element = focused as! AXUIElement
        var roleObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj) == .success,
           let role = roleObj as? String,
           role == "AXSecureTextField" {
            return true
        }
        var subroleObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleObj) == .success,
           let subrole = subroleObj as? String,
           subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    private func selectWordToLeft() {
        // Option + Shift + Left Arrow
        sendKeyCombo(keyCode: 123, flags: [.maskAlternate, .maskShift])
        usleep(45_000)
    }

    private func copyCurrentSelection() -> String? {
        let pasteboard = NSPasteboard.general
        let beforeChangeCount = pasteboard.changeCount
        sendKeyCombo(keyCode: 8, flags: [.maskCommand]) // 'c'

        for _ in 0..<15 {
            usleep(12_000)
            if pasteboard.changeCount != beforeChangeCount {
                return pasteboard.string(forType: .string)
            }
        }
        return nil
    }

    private func readTokenBeforeCaretViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObj) == .success,
              let focused = focusedObj else {
            return nil
        }
        let element = focused as! AXUIElement

        var rangeObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj) == .success,
              let rangeVal = rangeObj else {
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange), cfRange.location > 0 else {
            return nil
        }

        let start = max(0, cfRange.location - 64)
        let length = cfRange.location - start
        var queryRange = CFRange(location: start, length: length)
        guard let axQueryRange = AXValueCreate(.cfRange, &queryRange) else {
            return nil
        }

        var textBefore: String?
        var strObj: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axQueryRange,
            &strObj
        ) == .success, let str = strObj as? String {
            textBefore = str
        } else {
            var valObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valObj) == .success,
               let fullText = valObj as? String {
                let utf16 = fullText.utf16
                if let startIdx = utf16.index(utf16.startIndex, offsetBy: start, limitedBy: utf16.endIndex),
                   let endIdx = utf16.index(startIdx, offsetBy: length, limitedBy: utf16.endIndex) {
                    textBefore = String(utf16[startIdx..<endIdx])
                }
            }
        }

        guard let slice = textBefore, !slice.isEmpty else {
            return nil
        }

        // Take trailing non-whitespace characters (includes ',', '.', ';', '[', etc.)
        if let lastSpace = slice.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            let token = String(slice[slice.index(after: lastSpace)...])
            return token.isEmpty ? nil : token
        }
        return slice
    }

    private func detectSelectionViaAX() -> SelectionState {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObj) == .success,
              let focused = focusedObj else {
            return .unknown
        }
        let element = focused as! AXUIElement

        var selectedTextObj: CFTypeRef?
        let textErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextObj)
        if textErr == .success, let selected = selectedTextObj as? String {
            return selected.isEmpty ? .empty : .selected
        }

        var rangeObj: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj)
        if rangeErr == .success, let rangeVal = rangeObj {
            var cfRange = CFRange()
            if AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange) {
                return cfRange.length > 0 ? .selected : .empty
            }
        }

        return .unknown
    }

    private func sendKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
