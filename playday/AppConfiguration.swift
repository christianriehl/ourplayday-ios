import Foundation

enum AppConfiguration {
    private static let baseURLKey = "PLAYDAY_BASE_URL"
    private static let fallbackBaseURLString = "https://playday.christianriehl1.workers.dev"

    static var baseURL: URL? {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: baseURLKey) as? String
        let candidate = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let candidate, !candidate.isEmpty {
            return URL(string: candidate)
        }

        return URL(string: fallbackBaseURLString)
    }

    static func resolvedWebURL(for incomingURL: URL) -> URL {
        guard let scheme = incomingURL.scheme?.lowercased() else {
            return incomingURL
        }

        switch scheme {
        case "http", "https":
            return incomingURL
        default:
            if let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
               let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let resolvedURL = URL(string: target) {
                return resolvedURL
            }

            return baseURL ?? incomingURL
        }
    }
}
