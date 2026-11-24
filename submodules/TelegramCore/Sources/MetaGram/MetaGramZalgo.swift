import Foundation

/// MetaGram "Filter Zalgo": strips stacked combining marks ("Z̷͓a̸͖l̵̹g̶o̴") from texts.
public enum MetaGramZalgo {
    /// A character carrying more marks than this counts as zalgo.
    private static let zalgoThreshold = 3
    /// Marks kept on each character of a cleaned text (enough for real languages and emoji selectors).
    private static let keptMarks = 2

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    /// The cleaned text, or nil if the text has no zalgo (so it is left untouched).
    public static func clean(_ text: String) -> String? {
        var hasZalgo = false
        for character in text {
            var marks = 0
            for scalar in character.unicodeScalars where isMark(scalar) {
                marks += 1
            }
            if marks > zalgoThreshold {
                hasZalgo = true
                break
            }
        }
        if !hasZalgo {
            return nil
        }
        var result = String.UnicodeScalarView()
        for character in text {
            var marks = 0
            for scalar in character.unicodeScalars {
                if isMark(scalar) {
                    marks += 1
                    if marks > keptMarks {
                        continue
                    }
                }
                result.append(scalar)
            }
        }
        return String(result)
    }
}
