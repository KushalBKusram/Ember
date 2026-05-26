import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        Group {
            if let attributed = attributedString {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .textSelection(.enabled)
    }

    private var attributedString: AttributedString? {
        try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full
            )
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MarkdownText(text: "Here is some **bold** and *italic* text.")
        MarkdownText(text: "Inline `code` looks like this.")
        MarkdownText(text: "- Item one\n- Item two\n- Item three")
    }
    .padding()
}
