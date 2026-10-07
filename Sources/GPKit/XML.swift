/// OMM in NDM/XML (CCSDS 505.0-B-3): an `ndm` element holding `omm` elements, or a single `omm`. Each keyword is an
/// element named for it, under `header`, `metadata` and the blocks of `data`; a `USER_DEFINED` element is kept as
/// `USER_DEFINED_` and its `parameter` attribute. Element names are matched without their namespace prefix.
///
/// The reader is a small one written for this: elements, attributes, text, CDATA, comments, processing
/// instructions, the five named entities and numeric character references. A document type declaration is
/// refused, so no entity is ever defined by the file.
enum XML {

    final class Node {
        let name: String
        var attributes: [String: [UInt8]] = [:]
        var children: [Node] = []
        var text: [UInt8] = []
        let line: Int

        init(name: String, line: Int) {
            self.name = name
            self.line = line
        }

        /// The name without a namespace prefix.
        var localName: String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        func children(named local: String) -> [Node] {
            children.filter { $0.localName == local }
        }
    }

    static func readFile(_ bytes: [UInt8]) throws(Refusal) -> [ElementSetFile.Entry] {
        var scanner = Scanner(bytes: bytes)
        let root = try scanner.document()
        let messages: [Node]
        switch root.localName {
        case "omm": messages = [root]
        case "ndm": messages = root.children(named: "omm")
        default: throw Refusal(.malformedFile, "the root element is <\(root.name)>, neither <ndm> nor <omm>")
        }
        var entries: [ElementSetFile.Entry] = []
        var storage: [[UInt8]] = []
        for (record, message) in messages.enumerated() {
            var fields = OMM.Fields()
            var problem: Refusal?
            func add(_ keyword: String, _ value: [UInt8], line: Int) {
                guard problem == nil else { return }
                storage.append(value)
                if !fields.add(keyword, storage[storage.count - 1][...]) {
                    problem = Refusal(.duplicateKeyword, "\(keyword) appears twice in one message", field: keyword, line: line)
                }
            }
            func addLeaves(of block: Node) {
                for leaf in block.children {
                    let name = leaf.localName
                    if name == "COMMENT" { continue }
                    if name == "USER_DEFINED" {
                        add("USER_DEFINED_" + string(leaf.attributes["parameter"] ?? []), leaf.text, line: leaf.line)
                    } else if leaf.children.isEmpty {
                        add(name, leaf.text, line: leaf.line)
                    } else {
                        addLeaves(of: leaf)
                    }
                }
            }
            if let version = message.attributes["version"] { add("CCSDS_OMM_VERS", version, line: message.line) }
            for header in message.children(named: "header") { addLeaves(of: header) }
            for body in message.children(named: "body") {
                for segment in body.children(named: "segment") {
                    for metadata in segment.children(named: "metadata") { addLeaves(of: metadata) }
                    for data in segment.children(named: "data") { addLeaves(of: data) }
                }
            }
            if let problem {
                entries.append(.refusal(problem.located(record: record, line: message.line, catalogField: fields["NORAD_CAT_ID"].map { string($0) })))
            } else {
                entries.append(OMM.entry(fields, format: .xml, record: record, line: message.line))
            }
        }
        return entries
    }

    struct Scanner {
        let bytes: [UInt8]
        var i = 0
        var line = 1

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        func malformed(_ what: String) -> Refusal {
            i >= bytes.count ? Refusal(.cutShort, "the XML ends \(what)", line: line) : Refusal(.malformedFile, "not well-formed XML: \(what)", line: line)
        }

        func at(_ word: String) -> Bool {
            let w = Array(word.utf8)
            return i + w.count <= bytes.count && bytes[i..<(i + w.count)].elementsEqual(w)
        }

        mutating func advance(_ count: Int = 1) {
            for _ in 0..<count where i < bytes.count {
                if bytes[i] == 0x0A { line += 1 }
                i += 1
            }
        }

        /// Moves past the next occurrence of `word`.
        mutating func skip(past word: String, _ what: String) throws(Refusal) {
            while i < bytes.count, !at(word) { advance() }
            guard i < bytes.count else { throw malformed("inside \(what)") }
            advance(word.utf8.count)
        }

        mutating func skipWhitespace() {
            while i < bytes.count, bytes[i].isWhitespace { advance() }
        }

        static func isNameByte(_ c: UInt8) -> Bool {
            c.isDigit || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x2D || c == 0x2E || c == 0x3A || c >= 0x80
        }

        mutating func name() throws(Refusal) -> String {
            let start = i
            while i < bytes.count, Scanner.isNameByte(bytes[i]) { i += 1 }
            guard i > start else { throw malformed("where a name should be") }
            return string(bytes[start..<i])
        }

        /// The reference that starts at the ampersand under the cursor, as UTF-8.
        mutating func reference() throws(Refusal) -> [UInt8] {
            guard let end = bytes[i...].prefix(12).firstIndex(of: 0x3B) else { throw malformed("an ampersand that starts no reference") }
            let body = string(bytes[(i + 1)..<end])
            i = end + 1
            switch body {
            case "lt": return [0x3C]
            case "gt": return [0x3E]
            case "amp": return [0x26]
            case "quot": return [0x22]
            case "apos": return [0x27]
            default:
                var value: UInt32?
                if body.hasPrefix("#x") {
                    value = UInt32(body.dropFirst(2), radix: 16)
                } else if body.hasPrefix("#") {
                    value = UInt32(body.dropFirst(1), radix: 10)
                }
                guard let value, let scalar = Unicode.Scalar(value) else { throw malformed("the reference &\(body); which this reader does not define") }
                return Array(String(Character(scalar)).utf8)
            }
        }

        mutating func document() throws(Refusal) -> Node {
            var stack: [Node] = []
            var root: Node?
            while i < bytes.count {
                if bytes[i] != 0x3C {
                    // text
                    if bytes[i] == 0x26 {
                        let resolved = try reference()
                        guard let top = stack.last else { throw malformed("text outside the root element") }
                        top.text += resolved
                    } else {
                        guard let top = stack.last else {
                            guard bytes[i].isWhitespace else { throw malformed("text outside the root element") }
                            advance()
                            continue
                        }
                        top.text.append(bytes[i])
                        advance()
                    }
                    continue
                }
                if at("<?") {
                    try skip(past: "?>", "a processing instruction")
                } else if at("<!--") {
                    try skip(past: "-->", "a comment")
                } else if at("<![CDATA[") {
                    guard let top = stack.last else { throw malformed("a CDATA section outside the root element") }
                    advance(9)
                    let start = i
                    while i < bytes.count, !at("]]>") { advance() }
                    guard i < bytes.count else { throw malformed("inside a CDATA section") }
                    top.text += bytes[start..<i]
                    advance(3)
                } else if at("<!") {
                    throw Refusal(.malformedFile, "the XML has a document type declaration, which this reader does not read", line: line)
                } else if at("</") {
                    advance(2)
                    let closing = try name()
                    skipWhitespace()
                    guard i < bytes.count, bytes[i] == 0x3E else { throw malformed("in the closing tag </\(closing)") }
                    advance()
                    guard let top = stack.popLast(), top.name == closing else { throw malformed("</\(closing)> closes an element that is not open") }
                    if stack.isEmpty { root = top }
                } else {
                    guard root == nil else { throw malformed("a second root element") }
                    guard stack.count < 64 else { throw Refusal(.malformedFile, "the XML is nested more than 64 deep", line: line) }
                    advance()
                    let node = Node(name: try name(), line: line)
                    var selfClosing = false
                    while true {
                        skipWhitespace()
                        guard i < bytes.count else { throw malformed("inside the tag <\(node.name)") }
                        if bytes[i] == 0x3E {
                            advance()
                            break
                        }
                        if at("/>") {
                            advance(2)
                            selfClosing = true
                            break
                        }
                        let attribute = try name()
                        skipWhitespace()
                        guard i < bytes.count, bytes[i] == 0x3D else { throw malformed("in the attribute \(attribute) of <\(node.name)>") }
                        advance()
                        skipWhitespace()
                        guard i < bytes.count, bytes[i] == 0x22 || bytes[i] == 0x27 else { throw malformed("in the attribute \(attribute) of <\(node.name)>") }
                        let quote = bytes[i]
                        advance()
                        var value: [UInt8] = []
                        while i < bytes.count, bytes[i] != quote {
                            guard bytes[i] != 0x3C else { throw malformed("a < inside the attribute \(attribute)") }
                            if bytes[i] == 0x26 {
                                value += try reference()
                            } else {
                                value.append(bytes[i])
                                advance()
                            }
                        }
                        guard i < bytes.count else { throw malformed("inside the attribute \(attribute)") }
                        advance()
                        guard node.attributes[attribute] == nil else { throw malformed("the attribute \(attribute) twice on <\(node.name)>") }
                        node.attributes[attribute] = value
                    }
                    stack.last?.children.append(node)
                    if selfClosing {
                        if stack.isEmpty { root = node }
                    } else {
                        stack.append(node)
                    }
                }
            }
            guard stack.isEmpty else { throw Refusal(.cutShort, "the XML ends with <\(stack.last!.name)> still open", line: line) }
            guard let root else { throw Refusal(.malformedFile, "the XML has no element") }
            return root
        }
    }
}
