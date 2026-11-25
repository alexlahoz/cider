import Foundation

/// Minimal parser for Valve's text KeyValues format (.vdf / .acf).
indirect enum VDF: Sendable {
    case string(String)
    case object([(String, VDF)])

    subscript(key: String) -> VDF? {
        guard case .object(let pairs) = self else { return nil }
        let k = key.lowercased()
        return pairs.first { $0.0.lowercased() == k }?.1
    }

    /// Follows a path of keys, case-insensitively.
    func at(_ keys: String...) -> VDF? {
        var cur: VDF? = self
        for k in keys { cur = cur?[k] }
        return cur
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int? { string.flatMap { Int($0) } }

    var children: [(String, VDF)] {
        if case .object(let pairs) = self { return pairs }
        return []
    }

    static func parse(contentsOf url: URL) -> VDF? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> VDF? {
        var tokens: [String] = []
        var kinds: [Bool] = [] // true = brace token
        let chars = Array(text.unicodeScalars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                var s = String.UnicodeScalarView()
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        let n = chars[i + 1]
                        switch n {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        case "\\": s.append("\\")
                        case "\"": s.append("\"")
                        default: s.append("\\"); s.append(n)
                        }
                        i += 2
                        continue
                    }
                    s.append(chars[i]); i += 1
                }
                i += 1
                tokens.append(String(s)); kinds.append(false)
            } else if c == "{" || c == "}" {
                tokens.append(String(c)); kinds.append(true); i += 1
            } else if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
            } else if c.properties.isWhitespace {
                i += 1
            } else {
                var s = String.UnicodeScalarView()
                while i < chars.count && !chars[i].properties.isWhitespace && chars[i] != "{" && chars[i] != "}" && chars[i] != "\"" {
                    s.append(chars[i]); i += 1
                }
                tokens.append(String(s)); kinds.append(false)
            }
        }
        var pos = 0
        func parseObject() -> [(String, VDF)] {
            var pairs: [(String, VDF)] = []
            while pos < tokens.count {
                if kinds[pos] && tokens[pos] == "}" { pos += 1; return pairs }
                let key = tokens[pos]; pos += 1
                guard pos < tokens.count else { break }
                if kinds[pos] && tokens[pos] == "{" {
                    pos += 1
                    pairs.append((key, .object(parseObject())))
                } else if !kinds[pos] {
                    pairs.append((key, .string(tokens[pos]))); pos += 1
                } else { pos += 1 }
            }
            return pairs
        }
        let root = parseObject()
        return root.isEmpty ? nil : .object(root)
    }
}
