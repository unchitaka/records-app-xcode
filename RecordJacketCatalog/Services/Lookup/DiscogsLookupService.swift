import Foundation

protocol DiscogsLookupService {
    func search(fields: EditableFields) async throws -> [DiscogsCandidate]
}

protocol CoverImageMatchService {
    func findCandidate(using imageData: Data, fields: EditableFields) async -> DiscogsCandidate?
}

final class StubCoverImageMatchService: CoverImageMatchService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func findCandidate(using imageData: Data, fields: EditableFields) async -> DiscogsCandidate? {
        logger.info("Cover image match not implemented yet. Stub invoked for future extension path.")
        return nil
    }
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
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else {
            logger.info("Discogs lookup skipped: empty query")
            throw DiscogsLookupError.emptyQuery
        }

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

        guard let url = components.url else {
            logger.error("Discogs lookup failed: invalid URL components for query=\(query)")
            throw DiscogsLookupError.invalidResponse
        }

        logger.info("Discogs lookup query='\(query)'")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                logger.error("Discogs lookup failed: non-HTTP response")
                throw DiscogsLookupError.invalidResponse
            }

            guard http.statusCode == 200 else {
                if http.statusCode == 429 {
                    logger.error("Discogs lookup rate limited: status=429")
                    throw DiscogsLookupError.rateLimited
                }

                logger.error("Discogs lookup failed with HTTP status=\(http.statusCode)")
                throw DiscogsLookupError.httpStatus(http.statusCode)
            }

            do {
                let decoded = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
                let candidates = decoded.results.prefix(3).map {
                    DiscogsCandidate(
                        id: $0.id,
                        title: $0.title,
                        year: $0.year,
                        country: $0.country,
                        format: $0.format?.joined(separator: ", "),
                        resourceURL: $0.resourceURL
                    )
                }

                if candidates.isEmpty {
                    logger.info("Discogs lookup returned zero results")
                }

                return candidates
            } catch {
                logger.error("Discogs decoding failure: \(error.localizedDescription)")
                throw DiscogsLookupError.decodingFailed
            }
        } catch let error as DiscogsLookupError {
            throw error
        } catch {
            logger.error("Discogs network failure: \(error.localizedDescription)")
            throw DiscogsLookupError.networkFailure(error.localizedDescription)
        }
    }
}

enum DiscogsLookupError: LocalizedError {
    case missingToken
    case emptyQuery
    case invalidResponse
    case decodingFailed
    case httpStatus(Int)
    case rateLimited
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Discogs token missing. Configure DISCOGS_TOKEN in Info.plist or app environment."
        case .emptyQuery:
            return "Enter at least a title, artist, or catalog number before lookup."
        case .invalidResponse:
            return "Discogs returned an unexpected response format. Retry in a moment."
        case .decodingFailed:
            return "Discogs data could not be read. Retry; if this persists, refine your query."
        case .httpStatus(let code):
            return "Discogs request failed (HTTP \(code)). Verify token and try again."
        case .rateLimited:
            return "Discogs rate limit reached. Wait a bit and retry."
        case .networkFailure:
            return "Network error while contacting Discogs. Check connection and retry."
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
