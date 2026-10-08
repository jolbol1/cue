import Foundation

public struct ScriptBlock: Equatable {
    public enum Kind: Equatable { case paragraph, heading(Int), code, quote, bullet }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

public enum MarkdownScript {
    public static func parse(_ source: String, includeCode: Bool = false) -> [ScriptBlock] {
        let clean = source.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        var lines = clean.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) {
            lines.removeFirst(end + 1)
        }
        var blocks: [ScriptBlock] = [], paragraph: [String] = [], code: [String] = []
        var fence: String?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.init(kind: .paragraph, text: paragraph.joined(separator: " "))); paragraph = [] }
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let active = fence {
                if line.hasPrefix(active) {
                    if includeCode && !code.isEmpty { blocks.append(.init(kind: .code, text: code.joined(separator: "\n"))) }
                    code = []; fence = nil
                } else { code.append(raw) }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush(); let char = line.first!; fence = String(line.prefix(while: { $0 == char })); continue
            }
            if line.isEmpty { flush(); continue }
            if line.range(of: "^([-*_])(?:\\s*\\1){2,}$", options: .regularExpression) != nil { flush(); continue }
            if line.range(of: "^\\[[^]]+\\]:\\s*\\S", options: .regularExpression) != nil { continue }
            if line.hasPrefix("![") { continue }
            if line.hasPrefix("#"), let space = line.firstIndex(of: " ") {
                let prefix = line[..<space]
                if prefix.count <= 6 && prefix.allSatisfy({ $0 == "#" }) {
                    flush(); blocks.append(.init(kind: .heading(prefix.count), text: String(line[line.index(after: space)...]))); continue
                }
            }
            if line.hasPrefix(">") { flush(); blocks.append(.init(kind: .quote, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue }
            if let range = line.range(of: "^(?:[-+*] |[0-9]+[.)] )", options: .regularExpression) {
                flush(); let body = String(line[range.upperBound...]).replacingOccurrences(of: "^\\[[ xX]\\]\\s*", with: "", options: .regularExpression)
                blocks.append(.init(kind: .bullet, text: body)); continue
            }
            paragraph.append(line)
        }
        flush()
        if includeCode && !code.isEmpty { blocks.append(.init(kind: .code, text: code.joined(separator: "\n"))) }
        return blocks
    }
}

public enum PedalReport {
    // Stream Deck Pedal (0x0fd9:0x0086): four header bytes, then L/C/R.
    public static func decode(_ bytes: [UInt8]) -> [Bool]? {
        guard bytes.count >= 7, bytes[0] == 1, bytes[1] == 0, bytes[2] == 3, bytes[3] == 0,
              bytes[4...6].allSatisfy({ $0 <= 1 }) else { return nil }
        return bytes[4...6].map { $0 == 1 }
    }
}

public enum ScrollMath {
    public static func advance(position: Double, velocity: Double, elapsed: Double, maximum: Double, loop: Bool) -> Double {
        let next = position + velocity * min(max(elapsed, 0), 0.1)
        if loop && velocity > 0 && next > maximum { return 0 }
        return min(max(0, next), max(0, maximum))
    }
}
