import Cocoa

final class EventTapManager {
    private enum TrackedModifier {
        case control
        case option
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var trackedModifier: TrackedModifier?
    private var otherInputOccurred = false
    private var pressTimestamp: Date?
    private let maxTapDuration: TimeInterval = 0.6

    private var typedWordBuffer = ""

    var isEnabled = true
    var isAutoSwitchEnabled = true {
        didSet {
            if !isAutoSwitchEnabled {
                typedWordBuffer = ""
            }
        }
    }

    func start() -> Bool {
        if eventTap != nil { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            resetTracking()
            typedWordBuffer = ""
            return
        }

        guard isEnabled else {
            resetTracking()
            typedWordBuffer = ""
            return
        }

        // Ignore synthetic events posted by TextReplacer
        if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.syntheticEventTag {
            return
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if trackedModifier != nil {
                otherInputOccurred = true
            }
            typedWordBuffer = ""

        case .keyDown:
            if trackedModifier != nil {
                otherInputOccurred = true
            }
            handleKeyDownForBuffer(event)

        case .flagsChanged:
            handleFlagsChanged(event.flags)

        default:
            break
        }
    }

    private func handleKeyDownForBuffer(_ event: CGEvent) {
        let flags = event.flags
        // Shortcuts (Cmd, Ctrl, Option) break the current word
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            typedWordBuffer = ""
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Backspace
        if keyCode == 51 {
            if !typedWordBuffer.isEmpty {
                typedWordBuffer.removeLast()
            }
            return
        }

        // Space triggers auto-switch check for the completed word
        if keyCode == 49 {
            let word = typedWordBuffer
            typedWordBuffer = ""
            guard isAutoSwitchEnabled, word.count >= 3 else { return }

            DispatchQueue.main.async {
                guard !TextReplacer.shared.isFocusedElementSecureTextField() else { return }
                let script = InputSourceManager.shared.currentScript()
                if let result = AutoSwitcher.checkAutoConvert(word, currentScript: script) {
                    TextReplacer.shared.autoReplaceWordBeforeSpace(
                        originalLength: word.count,
                        replacement: result.text,
                        targetScript: result.targetScript
                    )
                }
            }
            return
        }

        // Navigation / control keys clear the buffer
        let resetKeyCodes: Set<Int64> = [36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126]
        if resetKeyCodes.contains(keyCode) {
            typedWordBuffer = ""
            return
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }

        let str = String(utf16CodeUnits: chars, count: length)
        if str.contains(where: { $0.isWhitespace || $0.isNewline }) {
            typedWordBuffer = ""
        } else {
            typedWordBuffer.append(str)
            if typedWordBuffer.count > 64 {
                typedWordBuffer = ""
            }
        }
    }

    private func handleFlagsChanged(_ flags: CGEventFlags) {
        let relevant = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])

        if relevant.isEmpty {
            if let mod = trackedModifier, !otherInputOccurred,
               let start = pressTimestamp, Date().timeIntervalSince(start) <= maxTapDuration {
                let recentWord = typedWordBuffer
                typedWordBuffer = ""
                DispatchQueue.main.async {
                    switch mod {
                    case .control:
                        InputSourceManager.shared.cycleToNextLayout()
                    case .option:
                        TextReplacer.shared.convertSelectionOrLastWord(recentTypedWord: recentWord)
                    }
                }
            }
            resetTracking()
            return
        }

        if relevant == .maskControl {
            if trackedModifier == nil {
                trackedModifier = .control
                otherInputOccurred = false
                pressTimestamp = Date()
            } else if trackedModifier != .control {
                otherInputOccurred = true
            }
        } else if relevant == .maskAlternate {
            if trackedModifier == nil {
                trackedModifier = .option
                otherInputOccurred = false
                pressTimestamp = Date()
            } else if trackedModifier != .option {
                otherInputOccurred = true
            }
        } else {
            otherInputOccurred = true
        }
    }

    private func resetTracking() {
        trackedModifier = nil
        otherInputOccurred = false
        pressTimestamp = nil
    }
}
