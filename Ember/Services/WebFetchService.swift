import Foundation
import PDFKit
@preconcurrency import SwiftSoup

actor WebFetchService {
    static let shared = WebFetchService()

    private let session = URLSession(configuration: .ephemeral)

    // MARK: - URL detection

    nonisolated func detectURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { $0.url }
    }

    // MARK: - Fetch

    func fetchText(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebFetchError.badResponse
        }

        let mime = http.mimeType ?? ""
        if mime.contains("pdf") {
            guard let pdf = PDFDocument(data: data), let text = pdf.string else {
                throw WebFetchError.unreadableContent
            }
            return text
        }

        let encoding = Self.encoding(from: http) ?? .utf8
        guard let html = String(data: data, encoding: encoding) else {
            throw WebFetchError.unreadableContent
        }
        return extractText(from: html, baseURL: url)
    }

    // MARK: - HTML extraction

    private func extractText(from html: String, baseURL: URL) -> String {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else {
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        try? doc.select("script, style, nav, header, footer, aside, form, iframe").remove()

        let title = (try? doc.title()) ?? ""
        let body: String
        if let main = try? doc.select("main, article, [role=main]").first() {
            body = (try? main.text()) ?? ""
        } else {
            body = (try? doc.body()?.text()) ?? ""
        }
        return title.isEmpty ? body : "\(title)\n\n\(body)"
    }

    // MARK: - Helpers

    private static func encoding(from response: HTTPURLResponse) -> String.Encoding? {
        guard let name = response.textEncodingName else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }
}

enum WebFetchError: LocalizedError {
    case badResponse, unreadableContent
    var errorDescription: String? {
        switch self {
        case .badResponse: return "The URL returned an error."
        case .unreadableContent: return "Could not read content from that URL."
        }
    }
}
