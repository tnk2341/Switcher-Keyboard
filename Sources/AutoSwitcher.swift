import Cocoa

enum AutoSwitcher {
    /// Checks if a typed word should be auto-converted using macOS's built-in NSSpellChecker.
    static func checkAutoConvert(_ word: String, currentScript: LayoutScript) -> ConversionResult? {
        guard word.count >= 3 else { return nil }
        // Skip words containing digits or whitespace
        if word.contains(where: { $0.isNumber || $0.isWhitespace }) {
            return nil
        }

        let converted = TextConverter.convert(word, currentScript: currentScript)
        guard converted.text != word else { return nil }

        let sourceLang = currentScript == .latin ? "en" : "ru"
        let targetLang = converted.targetScript == .latin ? "en" : "ru"

        let checker = NSSpellChecker.shared
        // If the word is already valid in the current layout's language, keep it.
        if isValidWord(word, language: sourceLang, checker: checker) {
            return nil
        }

        // Convert only if the resulting text is a valid word in the target language.
        if isValidWord(converted.text, language: targetLang, checker: checker) {
            return converted
        }

        return nil
    }

    private static func isValidWord(_ word: String, language: String, checker: NSSpellChecker) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
}
