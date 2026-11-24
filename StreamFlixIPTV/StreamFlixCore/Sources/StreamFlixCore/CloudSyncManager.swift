import Foundation
import Combine

public struct CloudSyncPayload: Codable, Sendable {
    public var watchProgress: [String: WatchProgressRecord]?
    public var favoriteSeriesIds: [Int]?
    public var favoriteMovieIds: [Int]?
    public var favoriteChannelIds: [Int]?
    public var updatedAt: Date?

    public init(
        watchProgress: [String: WatchProgressRecord]?,
        favoriteSeriesIds: [Int]?,
        favoriteMovieIds: [Int]?,
        favoriteChannelIds: [Int]?,
        updatedAt: Date? = Date()
    ) {
        self.watchProgress = watchProgress
        self.favoriteSeriesIds = favoriteSeriesIds
        self.favoriteMovieIds = favoriteMovieIds
        self.favoriteChannelIds = favoriteChannelIds
        self.updatedAt = updatedAt
    }
}

/// Lightweight, zero-SDK Firebase Realtime Database REST sync for iPad, iPhone, Mac (and future TV sync).
@MainActor
public final class CloudSyncManager: ObservableObject {
    @Published public var databaseURLString: String {
        didSet {
            UserDefaults.standard.set(databaseURLString, forKey: urlStorageKey)
        }
    }
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var lastSyncError: String?

    private let urlStorageKey = "StreamFlixIPTV.FirebaseURL.v1"
    private var pushTask: Task<Void, Never>?

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init() {
        self.databaseURLString = UserDefaults.standard.string(forKey: "StreamFlixIPTV.FirebaseURL.v1") ?? ""
    }

    public var isConfigured: Bool {
        normalizedBaseURL != nil
    }

    private var normalizedBaseURL: String? {
        let trimmed = databaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    public static func sanitizeUserKey(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: ".#$[]/ ")
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: forbidden)
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "_")
        return joined.isEmpty ? "default_user" : joined
    }

    private func endpointURL(userKey: String) -> URL? {
        guard let base = normalizedBaseURL else { return nil }
        let safeKey = Self.sanitizeUserKey(userKey)
        return URL(string: "\(base)/streamflix/\(safeKey).json")
    }

    public func pullAndMerge(
        userKey: String,
        progressStore: WatchProgressStore,
        localFavorites: (series: Set<Int>, movies: Set<Int>, channels: Set<Int>)
    ) async -> (series: Set<Int>, movies: Set<Int>, channels: Set<Int>)? {
        guard let url = endpointURL(userKey: userKey) else { return nil }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastSyncError = "HTTP \(http.statusCode)"
                return nil
            }
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               str == "null" || str.isEmpty {
                // First time: push local state up to cloud
                await pushNow(userKey: userKey, progressStore: progressStore, favorites: localFavorites)
                return localFavorites
            }

            let remote = try decoder.decode(CloudSyncPayload.self, from: data)
            progressStore.mergeRemoteRecords(remote.watchProgress ?? [:])

            let mergedSeries = localFavorites.series.union(remote.favoriteSeriesIds ?? [])
            let mergedMovies = localFavorites.movies.union(remote.favoriteMovieIds ?? [])
            let mergedChannels = localFavorites.channels.union(remote.favoriteChannelIds ?? [])

            lastSyncedAt = Date()
            return (mergedSeries, mergedMovies, mergedChannels)
        } catch {
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    public func schedulePush(
        userKey: String,
        progressStore: WatchProgressStore,
        favorites: (series: Set<Int>, movies: Set<Int>, channels: Set<Int>)
    ) {
        guard isConfigured else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await pushNow(userKey: userKey, progressStore: progressStore, favorites: favorites)
        }
    }

    public func pushNow(
        userKey: String,
        progressStore: WatchProgressStore,
        favorites: (series: Set<Int>, movies: Set<Int>, channels: Set<Int>)
    ) async {
        guard let url = endpointURL(userKey: userKey) else { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let payload = CloudSyncPayload(
            watchProgress: progressStore.records,
            favoriteSeriesIds: Array(favorites.series).sorted(),
            favoriteMovieIds: Array(favorites.movies).sorted(),
            favoriteChannelIds: Array(favorites.channels).sorted(),
            updatedAt: Date()
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastSyncError = "HTTP \(http.statusCode)"
                return
            }
            lastSyncedAt = Date()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }
}
