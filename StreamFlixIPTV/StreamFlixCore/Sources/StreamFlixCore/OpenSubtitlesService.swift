import Foundation
import Combine

// MARK: - Subtitle Languages (EN / AR / ES)

public enum SubtitleLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en"
    case arabic = "ar"
    case spanish = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        case .spanish: return "Español"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .arabic: return "🇪🇬"
        case .spanish: return "🇪🇸"
        }
    }
}

// MARK: - OpenSubtitles Models

public struct OpenSubtitlesSubtitleResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileId: Int
    public let fileName: String
    public let release: String
    public let language: String
    public let downloadCount: Int
    public let ratings: Double
    public let fromTrusted: Bool
    public let fps: Double?
    public let featureTitle: String?
    public let year: Int?

    public init(
        id: String,
        fileId: Int,
        fileName: String,
        release: String,
        language: String,
        downloadCount: Int,
        ratings: Double,
        fromTrusted: Bool,
        fps: Double?,
        featureTitle: String?,
        year: Int?
    ) {
        self.id = id
        self.fileId = fileId
        self.fileName = fileName
        self.release = release
        self.language = language
        self.downloadCount = downloadCount
        self.ratings = ratings
        self.fromTrusted = fromTrusted
        self.fps = fps
        self.featureTitle = featureTitle
        self.year = year
    }
}

public enum OpenSubtitlesError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidURL
    case unauthorized
    case rateLimited
    case httpError(Int, String?)
    case noDownloadLink

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenSubtitles API Key is not set. Add it in Account → Subtitles."
        case .invalidURL:
            return "Could not build OpenSubtitles request URL."
        case .unauthorized:
            return "Invalid OpenSubtitles API Key. Please check your key in Account → Subtitles."
        case .rateLimited:
            return "OpenSubtitles rate limit or daily download quota reached. Try again later."
        case .httpError(let code, let message):
            if let message, !message.isEmpty {
                return "OpenSubtitles error (\(code)): \(message)"
            }
            return "OpenSubtitles request failed (HTTP \(code))."
        case .noDownloadLink:
            return "OpenSubtitles did not return a download link for this subtitle."
        }
    }
}

// MARK: - OpenSubtitles Settings Store

@MainActor
public final class OpenSubtitlesSettings: ObservableObject {
    public static let shared = OpenSubtitlesSettings()

    @Published public var apiKey: String {
        didSet {
            KeychainHelper.save(apiKey, account: keychainOpenSubtitlesAccount)
        }
    }

    @Published public var geminiAPIKey: String {
        didSet {
            KeychainHelper.save(geminiAPIKey, account: keychainGeminiAccount)
        }
    }

    @Published public var preferredLanguage: SubtitleLanguage {
        didSet {
            UserDefaults.standard.set(preferredLanguage.rawValue, forKey: preferredLangStorageKey)
        }
    }

    private let keychainOpenSubtitlesAccount = "opensubtitles.api_key"
    private let keychainGeminiAccount = "gemini.api_key"
    private let preferredLangStorageKey = "StreamFlixIPTV.PreferredSubtitleLang.v1"

    public init() {
        // Load from Keychain, migrating any legacy UserDefaults secrets once and removing them from plaintext UserDefaults.
        if let kcOS = KeychainHelper.load(account: "opensubtitles.api_key") {
            self.apiKey = kcOS
        } else if let legacyOS = UserDefaults.standard.string(forKey: "StreamFlixIPTV.OpenSubtitlesApiKey.v1"), !legacyOS.isEmpty {
            KeychainHelper.save(legacyOS, account: "opensubtitles.api_key")
            UserDefaults.standard.removeObject(forKey: "StreamFlixIPTV.OpenSubtitlesApiKey.v1")
            self.apiKey = legacyOS
        } else {
            self.apiKey = ""
        }

        if let kcGemini = KeychainHelper.load(account: "gemini.api_key") {
            self.geminiAPIKey = kcGemini
        } else if let legacyGemini = UserDefaults.standard.string(forKey: "StreamFlixIPTV.GeminiApiKey.v1"), !legacyGemini.isEmpty {
            KeychainHelper.save(legacyGemini, account: "gemini.api_key")
            UserDefaults.standard.removeObject(forKey: "StreamFlixIPTV.GeminiApiKey.v1")
            self.geminiAPIKey = legacyGemini
        } else {
            self.geminiAPIKey = ""
        }

        let savedLang = UserDefaults.standard.string(forKey: "StreamFlixIPTV.PreferredSubtitleLang.v1") ?? "en"
        self.preferredLanguage = SubtitleLanguage(rawValue: savedLang) ?? .english
    }

    public var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedGeminiAPIKey: String {
        geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isConfigured: Bool {
        !trimmedAPIKey.isEmpty
    }

    public var isGeminiConfigured: Bool {
        !trimmedGeminiAPIKey.isEmpty
    }
}

// MARK: - OpenSubtitles REST API v1 Client

public struct OpenSubtitlesService: Sendable {
    private static let baseURL = "https://api.opensubtitles.com/api/v1"
    private static let userAgent = "StreamFlixIPTV v1.0"

    public init() {}

    /// Extracts a clean title (and optional year) from noisy IPTV item titles.
    public static func cleanSearchQuery(from rawTitle: String, kind: MediaKind) -> (query: String, year: Int?) {
        var text = rawTitle
        if kind == .episode {
            if let bulletRange = text.range(of: " • ") {
                text = String(text[..<bulletRange.lowerBound])
            } else if let dashRange = text.range(of: " — ") {
                text = String(text[..<dashRange.lowerBound])
            }
        }

        // Extract trailing/embedded 4-digit year like (2023) or 2023
        var extractedYear: Int?
        if let yearRegex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20\d{2})\b"#),
           let match = yearRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            extractedYear = Int(text[range])
        }

        // Strip common IPTV category prefixes like "EN - ", "AR | ", "ANIME - ", "4K - "
        let prefixPattern = #"(?i)^(?:EN|AR|TR|FR|ES|DE|IT|ANIME|VIP|4K|UHD|FHD|HD|SD|MULTI|SUB|DUB|NETFLIX|APPLE|HBO|DISNEY)\s*[-:|]+\s*"#
        if let prefixRegex = try? NSRegularExpression(pattern: prefixPattern) {
            text = prefixRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }

        // Strip common IPTV prefixes/tags like [4K], (EN), 1080p, WEB-DL, etc.
        let stripPatterns = [
            #"\[[^\]]*\]"#,
            #"\((?:19\d{2}|20\d{2}|4K|HD|FHD|UHD|SD|EN|AR|TR|FR|ES|MULTI|DUB|SUB)\)"#,
            #"(?i)\b(?:4K|UHD|FHD|1080p|720p|480p|WEB-DL|WEBRip|BluRay|HDRip|DVDRip|x264|x265|HEVC|H\.264|H\.265)\b"#,
            #"(?i)\bS\d+\s*E\d+\b"#
        ]
        for pattern in stripPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }

        text = text.replacingOccurrences(of: #"[\.\|_]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (text.isEmpty ? rawTitle : text, extractedYear)
    }

    public func searchSubtitles(
        apiKey: String,
        query: String,
        language: SubtitleLanguage = .english,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        mediaKind: MediaKind? = nil,
        year: Int? = nil
    ) async throws -> [OpenSubtitlesSubtitleResult] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenSubtitlesError.missingAPIKey }

        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }

        // For episodes, do NOT pass `year` because OpenSubtitles filters by episode air year, not series premiere year.
        let movieYear = (mediaKind == .movie) ? year : nil

        // 1. Exact search (with season & episode if provided)
        let exactResults = try await executeSearch(
            apiKey: key,
            query: cleanedQuery,
            language: language,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            mediaKind: mediaKind,
            year: movieYear
        )
        if !exactResults.isEmpty { return exactResults }

        // 2. Fallback for anime/IPTV with single-season absolute numbering (drop season_number, keep episode_number)
        if mediaKind == .episode, seasonNumber != nil, episodeNumber != nil {
            let episodeOnlyResults = try await executeSearch(
                apiKey: key,
                query: cleanedQuery,
                language: language,
                seasonNumber: nil,
                episodeNumber: episodeNumber,
                mediaKind: .episode,
                year: nil
            )
            if !episodeOnlyResults.isEmpty { return episodeOnlyResults }
        }

        // 3. Broad fallback (query + language only, so user can still pick from all available releases)
        if seasonNumber != nil || episodeNumber != nil || movieYear != nil {
            let broadResults = try await executeSearch(
                apiKey: key,
                query: cleanedQuery,
                language: language,
                seasonNumber: nil,
                episodeNumber: nil,
                mediaKind: nil,
                year: nil
            )
            if !broadResults.isEmpty { return broadResults }
        }

        return []
    }

    private func executeSearch(
        apiKey: String,
        query: String,
        language: SubtitleLanguage,
        seasonNumber: Int?,
        episodeNumber: Int?,
        mediaKind: MediaKind?,
        year: Int?
    ) async throws -> [OpenSubtitlesSubtitleResult] {
        var components = URLComponents(string: "\(Self.baseURL)/subtitles")
        var items: [URLQueryItem] = []

        if let episodeNumber {
            items.append(URLQueryItem(name: "episode_number", value: String(episodeNumber)))
        }
        items.append(URLQueryItem(name: "languages", value: language.rawValue))
        items.append(URLQueryItem(name: "query", value: query.lowercased()))
        if let seasonNumber {
            items.append(URLQueryItem(name: "season_number", value: String(seasonNumber)))
        }
        if let mediaKind {
            switch mediaKind {
            case .movie:
                items.append(URLQueryItem(name: "type", value: "movie"))
            case .episode:
                items.append(URLQueryItem(name: "type", value: "episode"))
            case .live:
                break
            }
        }
        if let year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }

        // OpenSubtitles recommends alphabetical query parameter order
        components?.queryItems = items.sorted { $0.name < $1.name }

        guard let url = components?.url else { throw OpenSubtitlesError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let mapped: [OpenSubtitlesSubtitleResult] = decoded.data.compactMap { entry in
            guard let firstFile = entry.attributes.files?.first else { return nil }
            let releaseName = (entry.attributes.release?.isEmpty == false ? entry.attributes.release : nil)
                ?? firstFile.fileName
                ?? "English Subtitle"
            return OpenSubtitlesSubtitleResult(
                id: entry.id,
                fileId: firstFile.fileId,
                fileName: firstFile.fileName ?? "subtitle_\(firstFile.fileId).srt",
                release: releaseName,
                language: entry.attributes.language ?? "en",
                downloadCount: entry.attributes.downloadCount ?? 0,
                ratings: entry.attributes.ratings ?? 0,
                fromTrusted: entry.attributes.fromTrusted ?? false,
                fps: entry.attributes.fps,
                featureTitle: entry.attributes.featureDetails?.title,
                year: entry.attributes.featureDetails?.year
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.fromTrusted != rhs.fromTrusted {
                return lhs.fromTrusted && !rhs.fromTrusted
            }
            return lhs.downloadCount > rhs.downloadCount
        }
    }

    public func downloadSubtitle(apiKey: String, fileId: Int, preferredFileName: String? = nil) async throws -> (localURL: URL, remainingQuota: Int?) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenSubtitlesError.missingAPIKey }

        let cacheDir = try subtitleCacheDirectory()
        let cachedURL = cacheDir.appendingPathComponent("os_\(fileId).srt")
        if FileManager.default.fileExists(atPath: cachedURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cachedURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 0 {
            return (cachedURL, nil)
        }

        guard let endpoint = URL(string: "\(Self.baseURL)/download") else {
            throw OpenSubtitlesError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = DownloadRequest(fileId: fileId, subFormat: "srt")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard let linkString = decoded.link, let fileURL = URL(string: linkString) else {
            throw OpenSubtitlesError.noDownloadLink
        }

        let (srtData, fileResponse) = try await URLSession.shared.data(from: fileURL)
        if let http = fileResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenSubtitlesError.httpError(http.statusCode, "Failed to fetch subtitle file.")
        }

        try srtData.write(to: cachedURL, options: .atomic)
        return (cachedURL, decoded.remaining)
    }

    private func subtitleCacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("OpenSubtitles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200...299).contains(http.statusCode) { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenSubtitlesError.unauthorized
        }
        if http.statusCode == 429 || http.statusCode == 406 {
            throw OpenSubtitlesError.rateLimited
        }
        let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.message
        throw OpenSubtitlesError.httpError(http.statusCode, message)
    }
}

// MARK: - Private API DTOs

private struct SearchResponse: Decodable {
    let data: [SubtitleEntry]

    struct SubtitleEntry: Decodable {
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let language: String?
        let downloadCount: Int?
        let ratings: Double?
        let fromTrusted: Bool?
        let fps: Double?
        let release: String?
        let files: [FileInfo]?
        let featureDetails: FeatureDetails?

        enum CodingKeys: String, CodingKey {
            case language, ratings, fps, release, files
            case downloadCount = "download_count"
            case fromTrusted = "from_trusted"
            case featureDetails = "feature_details"
        }
    }

    struct FileInfo: Decodable {
        let fileId: Int
        let fileName: String?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case fileName = "file_name"
        }
    }

    struct FeatureDetails: Decodable {
        let title: String?
        let year: Int?
    }
}

private struct DownloadRequest: Encodable {
    let fileId: Int
    let subFormat: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case subFormat = "sub_format"
    }
}

private struct DownloadResponse: Decodable {
    let link: String?
    let fileName: String?
    let remaining: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case link, remaining, message
        case fileName = "file_name"
    }
}

private struct ErrorEnvelope: Decodable {
    let message: String?
}
