import Foundation

protocol DiscogsLookupService {
    func search(fields: EditableFields) async throws -> [DiscogsCandidate]
}

enum DiscogsConfig {
    static var token: String = "SET_ME"
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
