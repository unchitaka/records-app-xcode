import Foundation

protocol DiscogsLookupService {
    func searchCandidates(fields: EditableFields) async throws -> [DiscogsCandidate]
    func fetchReleaseDetails(for candidate: DiscogsCandidate) async throws -> DiscogsReleaseDetails
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

    func searchCandidates(fields: EditableFields) async throws -> [DiscogsCandidate] {
        let title = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = fields.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = fields.catalogNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty || !artist.isEmpty || !catalog.isEmpty else {
            throw DiscogsLookupError.emptyQuery
        }

        try validateToken()

        var components = URLComponents(string: "https://api.discogs.com/database/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: "10"),
            URLQueryItem(name: "token", value: DiscogsConfig.token)
        ]

        if !title.isEmpty { queryItems.append(URLQueryItem(name: "release_title", value: title)) }
        if !artist.isEmpty { queryItems.append(URLQueryItem(name: "artist", value: artist)) }
        if !catalog.isEmpty { queryItems.append(URLQueryItem(name: "catno", value: catalog)) }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw DiscogsLookupError.invalidResponse
        }

        logger.info("Discogs candidate search title='\(title)' artist='\(artist)' catalog='\(catalog)'")
        let data = try await performRequest(url: url)

        let decoded: DiscogsSearchResponse
        do {
            decoded = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        } catch {
            logger.error("Discogs candidate decoding failure: \(error.localizedDescription)")
            throw DiscogsLookupError.decodingFailed
        }

        let candidates = decoded.results.map { result in
            DiscogsCandidate(
                id: result.id,
                title: result.title,
                year: result.year,
                country: result.country,
                format: result.format?.joined(separator: ", "),
                resourceURL: result.resourceURL,
                thumb: result.thumb,
                uri: result.uri
            )
        }

        if candidates.isEmpty {
            throw DiscogsLookupError.zeroResults
        }

        return candidates
    }

    func fetchReleaseDetails(for candidate: DiscogsCandidate) async throws -> DiscogsReleaseDetails {
        try validateToken()

        let url: URL
        if let resource = candidate.resourceURL, let resourceURL = URL(string: resource) {
            var components = URLComponents(url: resourceURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: DiscogsConfig.token))
            components?.queryItems = items
            guard let resolved = components?.url else {
                throw DiscogsLookupError.invalidResponse
            }
            url = resolved
        } else {
            var components = URLComponents(string: "https://api.discogs.com/releases/\(candidate.id)")!
            components.queryItems = [URLQueryItem(name: "token", value: DiscogsConfig.token)]
            guard let resolved = components.url else {
                throw DiscogsLookupError.invalidResponse
            }
            url = resolved
        }

        logger.info("Discogs release detail fetch id=\(candidate.id)")
        let data = try await performRequest(url: url)

        let decoded: DiscogsReleaseResponse
        do {
            decoded = try JSONDecoder().decode(DiscogsReleaseResponse.self, from: data)
        } catch {
            logger.error("Discogs detail decoding failure: \(error.localizedDescription)")
            throw DiscogsLookupError.decodingFailed
        }

        let labels = (decoded.labels ?? []).map {
            DiscogsReleaseDetails.Label(id: $0.id, name: $0.name, catalogNumber: $0.catno)
        }
        let catalogNumbers = labels.compactMap(\.catalogNumber).filter { !$0.isEmpty }
        let formats = (decoded.formats ?? []).map {
            DiscogsReleaseDetails.Format(name: $0.name, qty: $0.qty, descriptions: $0.descriptions ?? [])
        }
        let artists = (decoded.artists ?? []).map {
            DiscogsReleaseDetails.Artist(id: $0.id, name: $0.name, anv: $0.anv, join: $0.join, role: $0.role, tracks: $0.tracks)
        }
        let images = (decoded.images ?? []).map {
            DiscogsReleaseDetails.ImageInfo(type: $0.type, uri: $0.uri, uri150: $0.uri150, width: $0.width, height: $0.height, resourceURL: $0.resourceURL)
        }

        return DiscogsReleaseDetails(
            id: decoded.id,
            title: decoded.title,
            year: decoded.year,
            country: decoded.country,
            formats: formats,
            labels: labels,
            catalogNumbers: catalogNumbers,
            artists: artists,
            genres: decoded.genres ?? [],
            styles: decoded.styles ?? [],
            notes: decoded.notes,
            thumb: decoded.thumb,
            images: images,
            uri: decoded.uri,
            resourceURL: decoded.resourceURL,
            status: decoded.status,
            masterID: decoded.masterID
        )
    }

    private func validateToken() throws {
        guard DiscogsConfig.isConfigured else {
            logger.error("Discogs token is not configured")
            throw DiscogsLookupError.missingToken
        }
    }

    private func performRequest(url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw DiscogsLookupError.invalidResponse
            }

            guard http.statusCode == 200 else {
                if http.statusCode == 429 {
                    throw DiscogsLookupError.rateLimited
                }
                throw DiscogsLookupError.httpStatus(http.statusCode)
            }

            return data
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
    case zeroResults
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
        case .zeroResults:
            return "No Discogs candidates found. Edit title/artist/catalog number and try again."
        case .invalidResponse:
            return "Discogs returned an unexpected response format. Retry in a moment."
        case .decodingFailed:
            return "Discogs data could not be parsed. Retry; if it persists, refine your query."
        case .httpStatus(let code):
            return "Discogs request failed (HTTP \(code)). Verify token and retry."
        case .rateLimited:
            return "Discogs rate limit reached. Wait a bit and retry."
        case .networkFailure:
            return "Network error while contacting Discogs. Check connection and retry."
        }
    }
}

private struct DiscogsSearchResponse: Codable {
    let results: [DiscogsSearchResult]
}

private struct DiscogsSearchResult: Codable {
    let id: Int
    let title: String
    let year: String?
    let country: String?
    let format: [String]?
    let resourceURL: String?
    let thumb: String?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, country, format, thumb, uri
        case resourceURL = "resource_url"
    }
}

private struct DiscogsReleaseResponse: Codable {
    let id: Int
    let title: String
    let year: Int?
    let country: String?
    let formats: [Format]?
    let labels: [Label]?
    let artists: [Artist]?
    let genres: [String]?
    let styles: [String]?
    let notes: String?
    let thumb: String?
    let images: [Image]?
    let uri: String?
    let resourceURL: String?
    let status: String?
    let masterID: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, year, country, formats, labels, artists, genres, styles, notes, thumb, images, uri, status
        case resourceURL = "resource_url"
        case masterID = "master_id"
    }

    struct Format: Codable {
        let name: String
        let qty: String?
        let descriptions: [String]?
    }

    struct Label: Codable {
        let id: Int?
        let name: String
        let catno: String?
    }

    struct Artist: Codable {
        let id: Int?
        let name: String
        let anv: String?
        let join: String?
        let role: String?
        let tracks: String?
    }

    struct Image: Codable {
        let type: String?
        let uri: String?
        let uri150: String?
        let width: Int?
        let height: Int?
        let resourceURL: String?

        enum CodingKeys: String, CodingKey {
            case type, uri, width, height
            case uri150 = "uri150"
            case resourceURL = "resource_url"
        }
    }
}
