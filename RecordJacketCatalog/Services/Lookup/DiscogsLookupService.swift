import Foundation

protocol DiscogsLookupService {
    func search(fields: EditableFields) async throws -> [DiscogsCandidate]
}

enum DiscogsConfig {
    private static let placeholder = "SET_ME"

    static var token: String {
        if let value = ProcessInfo.processInfo.environment["DISCOGS_TOKEN"], !value.isEmpty {
            return value
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "DISCOGS_TOKEN") as? String, !value.isEmpty {
            return value
        }

        return placeholder
    }

    static var isConfigured: Bool {
        token != placeholder
    }
}

final class LiveDiscogsLookupService: DiscogsLookupService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func search(fields: EditableFields) async throws -> [DiscogsCandidate] {
        let query = [fields.artist, fields.title, fields.catalogNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else { return [] }
        guard DiscogsConfig.isConfigured else {
            logger.error("Discogs token is not configured")
            throw DiscogsLookupError.missingToken
        }

        var components = URLComponents(string: "https://api.discogs.com/database/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: "3"),
            URLQueryItem(name: "token", value: DiscogsConfig.token)
        ]

        guard let url = components.url else { return [] }
        logger.info("Discogs lookup: \(query)")

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)

        return decoded.results.prefix(3).map {
            DiscogsCandidate(
                id: $0.id,
                title: $0.title,
                year: $0.year,
                country: $0.country,
                format: $0.format?.joined(separator: ", "),
                resourceURL: $0.resourceURL
            )
        }
    }
}

enum DiscogsLookupError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Discogs token missing. Configure DISCOGS_TOKEN in the app environment or Info.plist."
        }
    }
}

private struct DiscogsSearchResponse: Codable {
    let results: [DiscogsRelease]
}

private struct DiscogsRelease: Codable {
    let id: Int
    let title: String
    let year: String?
    let country: String?
    let format: [String]?
    let resourceURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, country, format
        case resourceURL = "resource_url"
    }
}
