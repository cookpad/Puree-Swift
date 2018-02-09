import Foundation

private let separator: Character = "."
private let allWildcard = "**"
private let wildcard = "*"

public struct TagPattern {
    struct Match {
        let captured: String?
    }

    public let pattern: String

    public init?(string patternString: String) {
        if TagPattern.isValidPattern(patternString) {
            pattern = patternString
        } else {
            return nil
        }
    }

    static func isValidPattern(_ pattern: String) -> Bool {
        let patternElements = pattern.split(separator: separator)
        let wildcards = patternElements.filter { $0 == allWildcard || $0 == wildcard }
        return wildcards.count <= 1
    }

    func match(in tag: String) -> Match? {
        if tag == pattern {
            return Match(captured: nil)
        }

        let patternElements = pattern.split(separator: separator)
        let tagElements = tag.split(separator: separator)
        guard let lastPatternElement = patternElements.last, let lastTagElement = tagElements.last else {
            return nil
        }

        func matched(patternElements: [String.SubSequence], tagElements: [String.SubSequence]) -> Bool {
            for (index, (pattern, tag)) in zip(patternElements, tagElements).enumerated() {
                if index == patternElements.count - 1 {
                    return true
                }
                if pattern != tag {
                    return false
                }
            }
            return true
        }

        if lastPatternElement == allWildcard {
            if matched(patternElements: patternElements, tagElements: tagElements) {
                let location = patternElements.count - 1
                let capturedLength = tagElements.count - location
                let capturedString: String
                if capturedLength > 0 {
                    capturedString = tagElements[location..<(location + capturedLength)].joined(separator: String(separator))
                } else {
                    capturedString = ""
                }
                return Match(captured: capturedString)
            }
        } else if lastPatternElement == wildcard && tagElements.count == patternElements.count {
            if !matched(patternElements: patternElements, tagElements: tagElements) {
                return nil
            }
            return Match(captured: String(lastTagElement))
        }
        return nil
    }
}
