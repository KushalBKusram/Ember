import SwiftUI

/// Block-level markdown renderer.
/// - Parses the source into a sequence of blocks (paragraphs, headings,
///   bullet/numbered lists, code blocks, blockquotes).
/// - Each block is rendered with the appropriate SwiftUI view: paragraphs and
///   headings use inline-attributed `Text`, lists render as stacked rows,
///   fenced code blocks render in a monospaced glass card.
struct MarkdownText: View {
    let text: String
    var foreground: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Per-block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let inline):
            inlineText(inline)

        case .heading(let level, let inline):
            inlineText(inline)
                .font(headingFont(level: level))
                .fontWeight(.semibold)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        inlineText(item)
                    }
                }
            }

        case .codeBlock(let lang, let content):
            VStack(alignment: .leading, spacing: 4) {
                if let lang, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.thinMaterial)
                    )
            }

        case .quote(let inline):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(inline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attr = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr).foregroundColor(foreground)
        }
        return Text(source).foregroundColor(foreground)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:  return .title2
        case 2:  return .title3
        case 3:  return .headline
        default: return .subheadline
        }
    }

    // MARK: - Block parser

    private enum Block {
        case paragraph(String)
        case heading(level: Int, String)
        case bulletList([String])
        case numberedList([String])
        case codeBlock(language: String?, String)
        case quote(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3))
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    body.append(inner)
                    i += 1
                }
                out.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    body.joined(separator: "\n")
                ))
                continue
            }

            // Heading
            if let level = Self.headingLevel(trimmed) {
                let stripped = String(
                    trimmed.drop(while: { $0 == "#" })
                        .drop(while: { $0 == " " })
                )
                out.append(.heading(level: level, stripped))
                i += 1
                continue
            }

            // Bullet list
            if Self.isBullet(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let inner = lines[i].trimmingCharacters(in: .whitespaces)
                    guard Self.isBullet(inner) else { break }
                    items.append(String(inner.dropFirst(2)))
                    i += 1
                }
                out.append(.bulletList(items))
                continue
            }

            // Numbered list
            if Self.numberedPrefixEnd(trimmed) != nil {
                var items: [String] = []
                while i < lines.count {
                    let inner = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let prefixEnd = Self.numberedPrefixEnd(inner) else { break }
                    items.append(String(inner[prefixEnd...]).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(.numberedList(items))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quote: [String] = []
                while i < lines.count {
                    let inner = lines[i].trimmingCharacters(in: .whitespaces)
                    guard inner.hasPrefix("> ") else { break }
                    quote.append(String(inner.dropFirst(2)))
                    i += 1
                }
                out.append(.quote(quote.joined(separator: " ")))
                continue
            }

            // Paragraph — accumulate consecutive non-empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }
            var paragraph = [line]
            i += 1
            while i < lines.count {
                let inner = lines[i]
                let innerTrim = inner.trimmingCharacters(in: .whitespaces)
                if innerTrim.isEmpty
                    || innerTrim.hasPrefix("```")
                    || innerTrim.hasPrefix(">")
                    || Self.isBullet(innerTrim)
                    || Self.numberedPrefixEnd(innerTrim) != nil
                    || Self.headingLevel(innerTrim) != nil {
                    break
                }
                paragraph.append(inner)
                i += 1
            }
            out.append(.paragraph(paragraph.joined(separator: " ")))
        }

        return out
    }

    // MARK: - Block detectors

    private static func headingLevel(_ s: String) -> Int? {
        let hashes = s.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6, s.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func isBullet(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let leader = s.prefix(2)
        return leader == "- " || leader == "* " || leader == "+ "
    }

    private static func numberedPrefixEnd(_ s: String) -> String.Index? {
        var idx = s.startIndex
        while idx < s.endIndex, s[idx].isNumber {
            idx = s.index(after: idx)
        }
        guard idx > s.startIndex, idx < s.endIndex, s[idx] == "." else { return nil }
        let after = s.index(after: idx)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return s.index(after: after)
    }
}

#Preview {
    ScrollView {
        MarkdownText(text: """
            # Heading 1
            ## Heading 2

            Here is **bold** and *italic* and `inline code` text.

            - First bullet
            - Second bullet with **bold**
            - Third bullet

            1. Numbered one
            2. Numbered two

            > A blockquote with some thoughts.

            ```swift
            let answer = 42
            print(answer)
            ```

            Trailing paragraph.
            """)
        .padding()
    }
}
