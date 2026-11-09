import Foundation

/// How a medication name is looked up in openFDA's drug labels, and whether
/// a returned label is really for it. Searching by the first word turned
/// "Vitamin D3" into "vitamin" and showed some other product's warnings, so
/// the whole name is searched first, and a label only counts when one of its
/// brand or generic names matches the search.
public enum DrugLabelSearch {
    /// Words that describe the dose or form, not the drug.
    static let doseWords: Set<String> = [
        "mg", "mcg", "ug", "g", "iu", "ml", "units", "unit", "tablet", "tablets", "tab", "tabs",
        "capsule", "capsules", "cap", "caps", "pill", "pills", "daily", "once", "twice", "weekly",
        "injection", "pen", "dose", "oral", "er", "xr", "sr", "xl", "dr", "cr", "hcl",
    ]

    /// The name's words without dose amounts and form words, lowercased:
    /// "Metoprolol succinate 25 mg" → ["metoprolol", "succinate"].
    public static func words(_ name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                guard !word.isEmpty, !doseWords.contains(word) else { return false }
                // "25", "0.5" (split to "0","5"), "25mg", "500mcg": amounts, not names.
                let letters = word.drop { $0.isNumber }
                return !letters.isEmpty && !doseWords.contains(String(letters))
            }
    }

    /// Search terms, best first: the whole cleaned name, then (for longer
    /// names) the first word on its own. Each is checked with `matches`.
    public static func terms(for name: String) -> [String] {
        let words = words(name)
        guard let first = words.first else { return [] }
        let full = words.joined(separator: " ")
        guard words.count > 1, first.count > 2 else { return full.count > 2 ? [full] : [] }
        return [full, first]
    }

    /// True when a label's brand or generic names match `term`: the same
    /// words, or one name made of the term's words plus salt or form words
    /// ("metoprolol" ↔ "metoprolol succinate"). "vitamin" doesn't match
    /// "vitamin d3 and calcium", and a different drug never matches.
    public static func matches(term: String, labelNames: [String]) -> Bool {
        let termWords = words(term)
        guard !termWords.isEmpty else { return false }
        return labelNames.contains { name in
            let nameWords = words(name)
            guard !nameWords.isEmpty else { return false }
            if nameWords == termWords { return true }
            // The label adds only a salt to the searched generic name.
            if termWords.count == 1, let first = termWords.first, nameWords.first == first,
               nameWords.dropFirst().allSatisfy(saltWords.contains) {
                return true
            }
            // The user typed the generic plus its salt.
            if nameWords.count == 1, let only = nameWords.first, termWords.first == only,
               termWords.dropFirst().allSatisfy(saltWords.contains) {
                return true
            }
            return false
        }
    }

    /// Salt and release-form words that don't change which drug it is.
    static let saltWords: Set<String> = [
        "succinate", "tartrate", "hydrochloride", "sodium", "potassium", "calcium", "maleate", "besylate",
        "mesylate", "citrate", "sulfate", "phosphate", "acetate", "fumarate", "bromide", "magnesium",
        "monohydrate", "dihydrate", "extended", "release", "delayed",
    ]
}
