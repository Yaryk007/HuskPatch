// SPDX-License-Identifier: GPL-2.0-or-later
// Play's descriptions are a little HTML (<br>, <b>, <a>, lists, entities), sometimes with markdown-style **bold** in the text:
// turned into an AttributedString SwiftUI's Text can show, links tappable.
import SwiftUI

enum PlayText {
    static func attributed(_ html: String) -> AttributedString {
        var out = AttributedString()
        var bold = 0, italic = 0, underline = 0
        var link: URL?
        var lists: [Int?] = []       // nil: bullets; a number: the next item's
        var s = Substring(html)

        func trailing() -> Int { out.characters.reversed().prefix { $0 == "\n" }.count }
        func newline(_ count: Int = 1) {
            if out.characters.isEmpty { return }
            let have = trailing()
            if have < count { out += AttributedString(String(repeating: "\n", count: count - have)) }
        }
        func emit(_ raw: Substring) {
            var text = decode(raw)
            // never more than one blank line, counting the breaks already written
            while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
            let room = 2 - trailing()
            let lead = text.prefix { $0 == "\n" }.count
            if lead > room { text.removeFirst(lead - max(0, room)) }
            if text.isEmpty { return }
            // each line that starts here: no indent, "* " and "- " lists as bullets
            var lines = text.components(separatedBy: "\n")
            for i in lines.indices where i > 0 || out.characters.isEmpty || out.characters.last == "\n" {
                var line = Substring(lines[i]).drop { $0 == " " || $0 == "\t" }
                if line.hasPrefix("* ") || line.hasPrefix("- ") { line = "• " + line.dropFirst(2) }
                lines[i] = String(line)
            }
            text = lines.joined(separator: "\n")
            var piece = AttributedString(text)
            if let md = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)),
               md.characters.count < text.count { piece = md }    // only when it really had markdown in it
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty {
                for run in piece.runs { piece[run.range].inlinePresentationIntent = intent.union(run.inlinePresentationIntent ?? []) }
            }
            if underline > 0 { piece.underlineStyle = .single }
            if let link { piece.link = link }
            out += piece
        }

        while !s.isEmpty {
            guard let lt = s.firstIndex(of: "<") else { emit(s); break }
            emit(s[..<lt])
            guard let gt = s[lt...].firstIndex(of: ">") else { emit(s[lt...]); break }
            let tag = s[s.index(after: lt)..<gt]
            s = s[s.index(after: gt)...]
            let closing = tag.hasPrefix("/")
            let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            switch name {
            case "br":
                if trailing() < 2 { out += AttributedString("\n") }
                if s.first == "\n" { s.removeFirst() }    // "<br>" and a line break are one break
            case "p", "div":
                newline(2)
            case "h1", "h2", "h3", "h4", "h5", "h6":
                newline(2)
                bold += closing ? -1 : 1
            case "b", "strong": bold = max(0, bold + (closing ? -1 : 1))
            case "i", "em": italic = max(0, italic + (closing ? -1 : 1))
            case "u": underline = max(0, underline + (closing ? -1 : 1))
            case "a":
                link = closing ? nil : attribute("href", in: tag).flatMap { URL(string: decode($0[...])) }
            case "ul", "ol":
                if closing { _ = lists.popLast(); newline(lists.isEmpty ? 2 : 1) } else { newline(); lists.append(name == "ol" ? 1 : nil) }
            case "li":
                if closing { newline(); break }
                newline()
                let depth = String(repeating: "   ", count: max(0, lists.count - 1))
                if let n = lists.last ?? nil {
                    out += AttributedString("\(depth)\(n). ")
                    lists[lists.count - 1] = n + 1
                } else {
                    out += AttributedString("\(depth)• ")
                }
            default: break
            }
        }

        // nothing hanging at either end
        while let c = out.characters.first, c.isWhitespace { out.removeSubrange(out.startIndex..<out.characters.index(after: out.startIndex)) }
        while let c = out.characters.last, c.isWhitespace { out.removeSubrange(out.characters.index(before: out.endIndex)..<out.endIndex) }

        // bare links in the text
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let plain = String(out.characters)
            for m in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = m.url, let r = Range(m.range, in: out), out[r].link == nil else { continue }
                out[r].link = url
            }
        }
        return out
    }

    /// The text alone, for a one-line preview.
    static func plain(_ html: String) -> String { String(attributed(html).characters) }

    private static func attribute(_ name: String, in tag: Substring) -> Substring? {
        guard let r = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
        var rest = tag[r.upperBound...]
        if let q = rest.first, q == "\"" || q == "'" {
            rest = rest.dropFirst()
            return rest.prefix { $0 != q }
        }
        return rest.prefix { !$0.isWhitespace }
    }

    private static let entities: [Substring: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "ndash": "–", "mdash": "—",
        "hellip": "…", "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·", "laquo": "«", "raquo": "»",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "euro": "€", "pound": "£", "yen": "¥", "deg": "°",
    ]

    private static func decode(_ s: Substring) -> String {
        guard s.contains("&") else { return String(s) }
        var out = ""
        var rest = s
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semi]
                var value: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    value = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    value = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    value = entities[name]
                }
                if let value { out += value; rest = after[after.index(after: semi)...]; continue }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }
}
