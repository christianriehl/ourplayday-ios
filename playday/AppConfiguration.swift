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

    static var baseHost: String? {
        baseURL?.host?.lowercased()
    }

    static var associatedDomains: [String] {
        guard let host = baseHost else {
            return []
        }

        return ["applinks:\(host)"]
    }

    static func shouldOpenInternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        guard scheme == "http" || scheme == "https" else {
            return false
        }

        guard let host = url.host?.lowercased(),
              let baseHost else {
            return false
        }

        return host == baseHost
    }

    static func resolvedWebURL(for incomingURL: URL) -> URL {
        if shouldOpenInternally(incomingURL) {
            return incomingURL
        }

        guard let scheme = incomingURL.scheme?.lowercased() else {
            return incomingURL
        }

        if scheme != "http" && scheme != "https",
           let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
           let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let resolvedURL = URL(string: target) {
            return shouldOpenInternally(resolvedURL) ? resolvedURL : (baseURL ?? incomingURL)
        }

        return baseURL ?? incomingURL
    }
}
