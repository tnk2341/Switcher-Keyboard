import Foundation

enum LayoutScript: Equatable {
    case latin
    case cyrillic
}

struct ConversionResult: Equatable {
    let text: String
    let targetScript: LayoutScript
}

enum TextConverter {
    // U.S. QWERTY -> RussianWin (Russian - PC, ID 19458)
    static let latinToCyrillicMap: [Character: Character] = [
        "`": "ё", "~": "Ё",
        "q": "й", "Q": "Й",
        "w": "ц", "W": "Ц",
        "e": "у", "E": "У",
        "r": "к", "R": "К",
        "t": "е", "T": "Е",
        "y": "н", "Y": "Н",
        "u": "г", "U": "Г",
        "i": "ш", "I": "Ш",
        "o": "щ", "O": "Щ",
        "p": "з", "P": "З",
        "[": "х", "{": "Х",
        "]": "ъ", "}": "Ъ",
        "a": "ф", "A": "Ф",
        "s": "ы", "S": "Ы",
        "d": "в", "D": "В",
        "f": "а", "F": "А",
        "g": "п", "G": "П",
        "h": "р", "H": "Р",
        "j": "о", "J": "О",
        "k": "л", "K": "Л",
        "l": "д", "L": "Д",
        ";": "ж", ":": "Ж",
        "'": "э", "\"": "Э",
        "z": "я", "Z": "Я",
        "x": "ч", "X": "Ч",
        "c": "с", "C": "С",
        "v": "м", "V": "М",
        "b": "и", "B": "И",
        "n": "т", "N": "Т",
        "m": "ь", "M": "Ь",
        ",": "б", "<": "Б",
        ".": "ю", ">": "Ю"
    ]

    // Cyrillic letters -> U.S. QWERTY keys (RussianWin)
    static let cyrillicToLatinMap: [Character: Character] = [
        "ё": "`", "Ё": "~",
        "й": "q", "Й": "Q",
        "ц": "w", "Ц": "W",
        "у": "e", "У": "E",
        "к": "r", "К": "R",
        "е": "t", "Е": "T",
        "н": "y", "Н": "Y",
        "г": "u", "Г": "U",
        "ш": "i", "Ш": "I",
        "щ": "o", "Щ": "O",
        "з": "p", "З": "P",
        "х": "[", "Х": "{",
        "ъ": "]", "Ъ": "}",
        "ф": "a", "Ф": "A",
        "ы": "s", "Ы": "S",
        "в": "d", "В": "D",
        "а": "f", "А": "F",
        "п": "g", "П": "G",
        "р": "h", "Р": "H",
        "о": "j", "О": "J",
        "л": "k", "Л": "K",
        "д": "l", "Д": "L",
        "ж": ";", "Ж": ":",
        "э": "'", "Э": "\"",
        "я": "z", "Я": "Z",
        "ч": "x", "Ч": "X",
        "с": "c", "С": "C",
        "м": "v", "М": "V",
        "и": "b", "И": "B",
        "т": "n", "Т": "N",
        "ь": "m", "Ь": "M",
        "б": ",", "Б": "<",
        "ю": ".", "Ю": ">"
    ]

    /// Converts characters according to the current keyboard layout script:
    /// - If `currentScript == .latin`, translates ONLY Latin-mapped chars to Cyrillic and targets `.cyrillic`.
    /// - If `currentScript == .cyrillic`, translates ONLY Cyrillic-mapped chars to Latin and targets `.latin`.
    /// - If nothing changed under the current script (e.g. user selected Russian text while on U.S. layout),
    ///   falls back to translating the opposite script.
    static func convert(_ text: String, currentScript: LayoutScript) -> ConversionResult {
        let primary = translate(text, using: currentScript == .latin ? latinToCyrillicMap : cyrillicToLatinMap)
        if primary != text {
            return ConversionResult(
                text: primary,
                targetScript: currentScript == .latin ? .cyrillic : .latin
            )
        }

        let fallbackTarget: LayoutScript = currentScript
        let fallbackMap = currentScript == .latin ? cyrillicToLatinMap : latinToCyrillicMap
        let fallback = translate(text, using: fallbackMap)
        if fallback != text {
            return ConversionResult(text: fallback, targetScript: fallbackTarget)
        }

        return ConversionResult(
            text: text,
            targetScript: currentScript == .latin ? .cyrillic : .latin
        )
    }

    private static func translate(_ text: String, using map: [Character: Character]) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for ch in text {
            out.append(map[ch] ?? ch)
        }
        return out
    }
}
