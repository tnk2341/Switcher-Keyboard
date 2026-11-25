import Foundation

@main
enum ConverterTests {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fputs("FAIL: \(message)\n  expected: \(expected)\n  actual:   \(actual)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        // 1. Pure Latin -> Cyrillic when on Latin layout
        do {
            let res = TextConverter.convert("ghbdtn", currentScript: .latin)
            assertEqual(res.text, "привет", "Pure Latin -> Cyrillic")
            assertEqual(res.targetScript, .cyrillic, "Target script should be Cyrillic")
        }

        // 2. Pure Cyrillic -> Latin when on Cyrillic layout
        do {
            let res = TextConverter.convert("руддщ", currentScript: .cyrillic)
            assertEqual(res.text, "hello", "Pure Cyrillic -> Latin")
            assertEqual(res.targetScript, .latin, "Target script should be Latin")
        }

        // 3. Mixed Cyrillic + Latin when on Latin layout -> convert ONLY Latin to Cyrillic
        do {
            let res = TextConverter.convert("приdtn", currentScript: .latin)
            assertEqual(res.text, "привет", "Mixed word on Latin layout: only Latin chars converted")
            assertEqual(res.targetScript, .cyrillic, "Target script should be Cyrillic")
        }

        // 4. Mixed Latin + Cyrillic when on Cyrillic layout -> convert ONLY Cyrillic to Latin
        do {
            let res = TextConverter.convert("helдщ", currentScript: .cyrillic)
            assertEqual(res.text, "hello", "Mixed word on Cyrillic layout: only Cyrillic chars converted")
            assertEqual(res.targetScript, .latin, "Target script should be Latin")
        }

        // 5. Mixed with punctuation preserved on Cyrillic -> Latin
        do {
            let res = TextConverter.convert("руддщ, world!", currentScript: .cyrillic)
            assertEqual(res.text, "hello, world!", "Mixed sentence on Cyrillic layout preserves ASCII punctuation & Latin")
            assertEqual(res.targetScript, .latin, "Target script should be Latin")
        }

        // 6. Uppercase and special keys (RussianWin)
        do {
            let res = TextConverter.convert("Ghbdtn~", currentScript: .latin)
            assertEqual(res.text, "ПриветЁ", "Uppercase and tilde->Ё")
            assertEqual(res.targetScript, .cyrillic, "Target script should be Cyrillic")
        }

        // 7. Fallback when selection is pure Cyrillic while on Latin layout
        do {
            let res = TextConverter.convert("руддщ", currentScript: .latin)
            assertEqual(res.text, "hello", "Fallback converts Cyrillic->Latin if no Latin chars present")
            assertEqual(res.targetScript, .latin, "Fallback target script should be Latin")
        }

        // 8. AutoSwitcher: valid English word is NOT converted
        do {
            let res = AutoSwitcher.checkAutoConvert("hello", currentScript: .latin)
            assertEqual(res, nil, "Valid English word should not auto-switch")
        }

        // 9. AutoSwitcher: wrong-layout word -> auto-converted via NSSpellChecker
        do {
            let res = AutoSwitcher.checkAutoConvert("ghjuhfvvf", currentScript: .latin)
            assertEqual(res?.text, "программа", "Wrong-layout Russian word should auto-switch")
            assertEqual(res?.targetScript, .cyrillic, "Auto-switch target should be Cyrillic")
        }

        // 10. AutoSwitcher: wrong-layout English word typed in Russian -> auto-converted
        do {
            let res = AutoSwitcher.checkAutoConvert("руддщ", currentScript: .cyrillic)
            assertEqual(res?.text, "hello", "Wrong-layout English word should auto-switch")
            assertEqual(res?.targetScript, .latin, "Auto-switch target should be Latin")
        }

        // 11. Leading punctuation key (',' -> 'б') in ',eltn' -> 'будет'
        do {
            let res = TextConverter.convert(",eltn", currentScript: .latin)
            assertEqual(res.text, "будет", "Leading comma should convert to 'б'")
            assertEqual(res.targetScript, .cyrillic, "Target script should be Cyrillic")

            let autoRes = AutoSwitcher.checkAutoConvert(",eltn", currentScript: .latin)
            assertEqual(autoRes?.text, "будет", "AutoSwitcher should also convert ',eltn' -> 'будет'")
        }

        print("All ConverterTests passed!")
    }
}
