import Foundation

struct GFMExtendedAutolinkParser: Sendable {
    private let urlRegex: NSRegularExpression
    private let wwwRegex: NSRegularExpression
    private let emailProtocolRegex: NSRegularExpression
    private let emailRegex: NSRegularExpression

    private struct Candidate {
        let label: String
        let destination: String
        let length: Int
    }

    nonisolated init() {
        urlRegex = Self.makeRegex(
            pattern: #"https?://([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+)[^\s<]*"#
        )
        wwwRegex = Self.makeRegex(
            pattern: #"www\.([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+)[^\s<]*"#
        )
        emailProtocolRegex = Self.makeRegex(
            pattern: #"(?:mailto:|xmpp:)[A-Za-z0-9._%+\-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+(?:/[A-Za-z0-9@.]*)?"#
        )
        emailRegex = Self.makeRegex(
            pattern: #"[A-Za-z0-9.!$%&'*+/=?^_`{|}~\-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+"#
        )
    }

    private nonisolated static func makeRegex(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Failed to compile regular expression: \(error)")
        }
    }

    nonisolated func parse(_ text: String) -> [MarkdownInline] {
        let nsText = text as NSString
        var result: [MarkdownInline] = []
        var cursor = 0
        var textStart = 0

        while cursor < nsText.length {
            if let candidate = candidate(in: text, nsText: nsText, at: cursor) {
                appendText(from: textStart, to: cursor, nsText: nsText, into: &result)
                result.append(.link(destination: candidate.destination, title: nil, children: [.text(candidate.label)]))
                cursor += candidate.length
                textStart = cursor
            } else {
                cursor += 1
            }
        }

        appendText(from: textStart, to: nsText.length, nsText: nsText, into: &result)
        return result
    }

    private nonisolated func candidate(in text: String, nsText: NSString, at location: Int) -> Candidate? {
        if hasExtendedAutolinkBoundary(nsText: nsText, at: location) {
            if let candidate = urlCandidate(
                in: text,
                at: location,
                regex: urlRegex,
                domainGroup: 1,
                destinationPrefix: ""
            ) {
                return candidate
            }

            if let candidate = urlCandidate(
                in: text,
                at: location,
                regex: wwwRegex,
                domainGroup: 1,
                destinationPrefix: "http://"
            ) {
                return candidate
            }
        }

        if let candidate = emailProtocolCandidate(in: text, nsText: nsText, at: location) {
            return candidate
        }

        return emailCandidate(in: text, nsText: nsText, at: location)
    }

    private nonisolated func urlCandidate(
        in text: String,
        at location: Int,
        regex: NSRegularExpression,
        domainGroup: Int,
        destinationPrefix: String
    ) -> Candidate? {
        let nsText = text as NSString

        guard let match = anchoredMatch(regex, in: text, nsText: nsText, at: location) else {
            return nil
        }

        let domain = nsText.substring(with: match.range(at: domainGroup))
        guard isValidExtendedAutolinkDomain(domain) else {
            return nil
        }

        let label = trimmedURLLabel(nsText.substring(with: match.range))
        guard !label.isEmpty else {
            return nil
        }

        return Candidate(label: label, destination: "\(destinationPrefix)\(label)", length: (label as NSString).length)
    }

    private nonisolated func emailProtocolCandidate(
        in text: String,
        nsText: NSString,
        at location: Int
    ) -> Candidate? {
        guard let match = anchoredMatch(emailProtocolRegex, in: text, nsText: nsText, at: location) else {
            return nil
        }

        let label = trimmedEmailLabel(nsText.substring(with: match.range))
        guard isValidEmailAutolink(label.removingEmailProtocolPrefix()) else {
            return nil
        }

        return Candidate(label: label, destination: label, length: (label as NSString).length)
    }

    private nonisolated func emailCandidate(in text: String, nsText: NSString, at location: Int) -> Candidate? {
        guard let match = anchoredMatch(emailRegex, in: text, nsText: nsText, at: location) else {
            return nil
        }

        let label = trimmedEmailLabel(nsText.substring(with: match.range))
        guard isValidEmailAutolink(label) else {
            return nil
        }

        return Candidate(label: label, destination: "mailto:\(label)", length: (label as NSString).length)
    }

    private nonisolated func anchoredMatch(
        _ regex: NSRegularExpression,
        in text: String,
        nsText: NSString,
        at location: Int
    ) -> NSTextCheckingResult? {
        let range = NSRange(location: location, length: nsText.length - location)
        return regex.firstMatch(in: text, options: [.anchored], range: range)
    }

    private nonisolated func appendText(
        from start: Int,
        to end: Int,
        nsText: NSString,
        into result: inout [MarkdownInline]
    ) {
        guard end > start else {
            return
        }

        result.append(.text(nsText.substring(with: NSRange(location: start, length: end - start))))
    }

    private nonisolated func hasExtendedAutolinkBoundary(nsText: NSString, at location: Int) -> Bool {
        guard location > 0 else {
            return true
        }

        let previousRange = nsText.rangeOfComposedCharacterSequence(at: location - 1)
        let previous = nsText.substring(with: previousRange)
        return previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || "*_~(".contains(previous)
    }

    private nonisolated func trimmedURLLabel(_ label: String) -> String {
        var result = label

        while let last = result.last, "?!.,:*_~".contains(last) {
            result.removeLast()
        }

        while result.last == ")" && closingParenthesisCount(in: result) > openingParenthesisCount(in: result) {
            result.removeLast()
        }

        if result.last == ";", let entityRange = result.range(of: #"&[A-Za-z0-9]+;$"#, options: .regularExpression) {
            result.removeSubrange(entityRange)
        }

        return result
    }

    private nonisolated func trimmedEmailLabel(_ label: String) -> String {
        var result = label
        while result.last == "." {
            result.removeLast()
        }
        return result
    }

    private nonisolated func openingParenthesisCount(in text: String) -> Int {
        text.reduce(0) { count, character in
            character == "(" ? count + 1 : count
        }
    }

    private nonisolated func closingParenthesisCount(in text: String) -> Int {
        text.reduce(0) { count, character in
            character == ")" ? count + 1 : count
        }
    }

    private nonisolated func isValidExtendedAutolinkDomain(_ domain: String) -> Bool {
        let segments = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }) else {
            return false
        }

        guard segments.suffix(2).allSatisfy({ !$0.contains("_") }) else {
            return false
        }

        return segments.allSatisfy { segment in
            segment.allSatisfy { character in
                character.isLetter || character.isNumber || character == "_" || character == "-"
            }
        }
    }

    private nonisolated func isValidEmailAutolink(_ email: String) -> Bool {
        guard let atIndex = email.firstIndex(of: "@"), atIndex != email.startIndex else {
            return false
        }

        let domainStart = email.index(after: atIndex)
        guard domainStart < email.endIndex else {
            return false
        }

        let domain = email[domainStart...]
        guard let last = domain.last, last != "-", last != "_" else {
            return false
        }

        return domain.contains(".")
    }
}

private extension String {
    nonisolated func removingEmailProtocolPrefix() -> String {
        if lowercased().hasPrefix("mailto:") {
            return String(dropFirst("mailto:".count))
        }

        if lowercased().hasPrefix("xmpp:") {
            return String(dropFirst("xmpp:".count))
        }

        return self
    }
}
