import Foundation

// MARK: - Flexible JSON Helpers (Handles Xtream server String/Int/Double quirks)

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) -> String? {
        if let str = try? decodeIfPresent(String.self, forKey: key) {
            return str
        }
        if let intVal = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intVal)
        }
        if let doubleVal = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleVal)
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let intVal = try? decodeIfPresent(Int.self, forKey: key) {
            return intVal
        }
        if let str = try? decodeIfPresent(String.self, forKey: key), let parsed = Int(str) {
            return parsed
        }
        if let doubleVal = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleVal)
        }
        return nil
    }
}

// MARK: - Credentials & Profile

public struct XtreamCredentials: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var username: String
    public var password: String
    public var profileName: String

    public init(host: String, username: String, password: String, profileName: String = "My IPTV") {
        self.host = Self.normalizeHost(host)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeHost(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    public var playerAPIBaseURL: URL? {
        var components = URLComponents(string: "\(host)/player_api.php")
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        return components?.url
    }
}

// MARK: - Auth & Account Info

public struct XtreamAuthResponse: Codable, Sendable {
    public let userInfo: UserInfo
    public let serverInfo: ServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }

    public struct UserInfo: Codable, Sendable {
        public let username: String?
        public let status: String?
        public let expDate: String?
        public let activeCons: String?
        public let maxConnections: String?

        enum CodingKeys: String, CodingKey {
            case username, status
            case expDate = "exp_date"
            case activeCons = "active_cons"
            case maxConnections = "max_connections"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            username = c.decodeFlexibleString(forKey: .username)
            status = c.decodeFlexibleString(forKey: .status)
            expDate = c.decodeFlexibleString(forKey: .expDate)
            activeCons = c.decodeFlexibleString(forKey: .activeCons)
            maxConnections = c.decodeFlexibleString(forKey: .maxConnections)
        }

        public var isActive: Bool {
            status?.lowercased() == "active"
        }
    }

    public struct ServerInfo: Codable, Sendable {
        public let url: String?
        public let port: String?
        public let httpsPort: String?
        public let serverProtocol: String?
        public let timezone: String?

        enum CodingKeys: String, CodingKey {
            case url, port, timezone
            case httpsPort = "https_port"
            case serverProtocol = "server_protocol"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = c.decodeFlexibleString(forKey: .url)
            port = c.decodeFlexibleString(forKey: .port)
            httpsPort = c.decodeFlexibleString(forKey: .httpsPort)
            serverProtocol = c.decodeFlexibleString(forKey: .serverProtocol)
            timezone = c.decodeFlexibleString(forKey: .timezone)
        }
    }
}

// MARK: - Categories & Media Items

public struct MediaCategory: Codable, Identifiable, Hashable, Sendable {
    public let categoryId: String
    public let categoryName: String
    public let parentId: Int?

    public var id: String { categoryId }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = c.decodeFlexibleString(forKey: .categoryId) ?? UUID().uuidString
        categoryName = c.decodeFlexibleString(forKey: .categoryName) ?? "Category"
        parentId = c.decodeFlexibleInt(forKey: .parentId)
    }
}

public enum MediaKind: String, Codable, Sendable {
    case live
    case movie
    case episode
}

public struct LiveChannel: Codable, Identifiable, Hashable, Sendable {
    public let streamId: Int
    public let name: String
    public let streamIcon: String?
    public let epgChannelId: String?
    public let categoryId: String?
    public let tvArchive: Int?

    public var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case categoryId = "category_id"
        case tvArchive = "tv_archive"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamId = c.decodeFlexibleInt(forKey: .streamId) ?? 0
        name = c.decodeFlexibleString(forKey: .name) ?? "Channel"
        streamIcon = c.decodeFlexibleString(forKey: .streamIcon)
        epgChannelId = c.decodeFlexibleString(forKey: .epgChannelId)
        categoryId = c.decodeFlexibleString(forKey: .categoryId)
        tvArchive = c.decodeFlexibleInt(forKey: .tvArchive)
    }
}

public struct VODMovie: Codable, Identifiable, Hashable, Sendable {
    public let streamId: Int
    public let name: String
    public let streamIcon: String?
    public let rating: String?
    public let added: String?
    public let categoryId: String?
    public let containerExtension: String?

    public var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case rating
        case added
        case categoryId = "category_id"
        case containerExtension = "container_extension"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamId = c.decodeFlexibleInt(forKey: .streamId) ?? 0
        name = c.decodeFlexibleString(forKey: .name) ?? "Movie"
        streamIcon = c.decodeFlexibleString(forKey: .streamIcon)
        rating = c.decodeFlexibleString(forKey: .rating)
        added = c.decodeFlexibleString(forKey: .added)
        categoryId = c.decodeFlexibleString(forKey: .categoryId)
        containerExtension = c.decodeFlexibleString(forKey: .containerExtension)
    }
}

public struct SeriesItem: Codable, Identifiable, Hashable, Sendable {
    public let seriesId: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let cast: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: String?
    public let categoryId: String?

    public var id: Int { seriesId }

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name, cover, plot, cast, genre, rating
        case releaseDate = "releaseDate"
        case categoryId = "category_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesId = c.decodeFlexibleInt(forKey: .seriesId) ?? 0
        name = c.decodeFlexibleString(forKey: .name) ?? "Series"
        cover = c.decodeFlexibleString(forKey: .cover)
        plot = c.decodeFlexibleString(forKey: .plot)
        cast = c.decodeFlexibleString(forKey: .cast)
        genre = c.decodeFlexibleString(forKey: .genre)
        releaseDate = c.decodeFlexibleString(forKey: .releaseDate)
        rating = c.decodeFlexibleString(forKey: .rating)
        categoryId = c.decodeFlexibleString(forKey: .categoryId)
    }
}

public struct SeriesInfoResponse: Codable, Sendable {
    public let info: SeriesMetadata?
    public let episodes: [String: [EpisodeItem]]?

    public struct SeriesMetadata: Codable, Sendable {
        public let name: String?
        public let cover: String?
        public let plot: String?
        public let genre: String?
        public let rating: String?
        public let backdropPath: [String]?

        enum CodingKeys: String, CodingKey {
            case name, cover, plot, genre, rating
            case backdropPath = "backdrop_path"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.decodeFlexibleString(forKey: .name)
            cover = c.decodeFlexibleString(forKey: .cover)
            plot = c.decodeFlexibleString(forKey: .plot)
            genre = c.decodeFlexibleString(forKey: .genre)
            rating = c.decodeFlexibleString(forKey: .rating)
            backdropPath = try? c.decodeIfPresent([String].self, forKey: .backdropPath)
        }
    }
}

public struct EpisodeItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let episodeNum: Int
    public let title: String
    public let containerExtension: String?
    public let info: EpisodeInfo?
    public let season: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
        case season
    }

    public var displayEpisodeNumber: Int {
        let patterns = [
            #"(?i)\bS\d+\s*E(\d+)\b"#,
            #"(?i)\b(?:EP?|Episode)\s*(\d+)\b"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: title),
               let parsed = Int(title[range]) {
                return parsed
            }
        }
        return episodeNum
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        episodeNum = c.decodeFlexibleInt(forKey: .episodeNum) ?? 1
        title = c.decodeFlexibleString(forKey: .title) ?? "Episode"
        containerExtension = c.decodeFlexibleString(forKey: .containerExtension)
        info = try? c.decodeIfPresent(EpisodeInfo.self, forKey: .info)
        season = c.decodeFlexibleInt(forKey: .season)
    }

    public struct EpisodeInfo: Codable, Hashable, Sendable {
        public let durationSecs: Int?
        public let plot: String?
        public let movieImage: String?

        enum CodingKeys: String, CodingKey {
            case durationSecs = "duration_secs"
            case plot
            case movieImage = "movie_image"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            durationSecs = c.decodeFlexibleInt(forKey: .durationSecs)
            plot = c.decodeFlexibleString(forKey: .plot)
            movieImage = c.decodeFlexibleString(forKey: .movieImage)
        }
    }
}

// MARK: - Unified Playable Item

public struct PlayableItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let artworkURL: String?
    public let streamURL: URL
    public let kind: MediaKind
    public let seriesId: Int?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let nextEpisode: NextEpisodeRef?

    public struct NextEpisodeRef: Codable, Hashable, Sendable {
        public let episodeId: String
        public let title: String
        public let seasonNumber: Int
        public let episodeNumber: Int
        public let streamURL: URL
        public let artworkURL: String?

        public init(
            episodeId: String,
            title: String,
            seasonNumber: Int,
            episodeNumber: Int,
            streamURL: URL,
            artworkURL: String?
        ) {
            self.episodeId = episodeId
            self.title = title
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
            self.streamURL = streamURL
            self.artworkURL = artworkURL
        }
    }

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        artworkURL: String? = nil,
        streamURL: URL,
        kind: MediaKind,
        seriesId: Int? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        nextEpisode: NextEpisodeRef? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.kind = kind
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.nextEpisode = nextEpisode
    }
}
