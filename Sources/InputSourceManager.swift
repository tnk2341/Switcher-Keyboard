import Carbon
import Foundation

final class InputSourceManager {
    static let shared = InputSourceManager()

    private init() {}

    func enabledKeyboardLayouts() -> [TISInputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue as Any
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    func currentInputSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return inputSourceID(of: current)
    }

    func currentScript() -> LayoutScript {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .latin
        }
        if isCyrillicSource(current) {
            return .cyrillic
        }
        return .latin
    }

    func cycleToNextLayout() {
        let layouts = enabledKeyboardLayouts()
        guard layouts.count > 1 else { return }

        let currentID = currentInputSourceID()
        if let idx = layouts.firstIndex(where: { inputSourceID(of: $0) == currentID }) {
            let next = layouts[(idx + 1) % layouts.count]
            TISSelectInputSource(next)
        } else {
            TISSelectInputSource(layouts[0])
        }
    }

    func switchToScript(_ script: LayoutScript) {
        let layouts = enabledKeyboardLayouts()
        switch script {
        case .cyrillic:
            if let ru = layouts.first(where: { isCyrillicSource($0) }) {
                TISSelectInputSource(ru)
            }
        case .latin:
            // Prefer U.S. or ABC if available, otherwise first non-Cyrillic layout
            if let us = layouts.first(where: {
                let id = inputSourceID(of: $0) ?? ""
                return id == "com.apple.keylayout.US" || id == "com.apple.keylayout.ABC"
            }) {
                TISSelectInputSource(us)
            } else if let latin = layouts.first(where: { !isCyrillicSource($0) }) {
                TISSelectInputSource(latin)
            }
        }
    }

    private func inputSourceID(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func isCyrillicSource(_ source: TISInputSource) -> Bool {
        if let id = inputSourceID(of: source)?.lowercased(), id.contains("russian") {
            return true
        }
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
            if langs.contains("ru") {
                return true
            }
        }
        return false
    }
}
