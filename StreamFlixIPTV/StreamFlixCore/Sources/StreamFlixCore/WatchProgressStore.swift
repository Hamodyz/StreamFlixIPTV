import Foundation
import Combine

public struct WatchProgressRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let item: PlayableItem
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var updatedAt: Date

    public var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    public var isCompleted: Bool {
        progressFraction >= 0.93
    }

    /// Rewinds slightly (2s) on resume so the user gets context when returning from a long pause.
    public var resumeTargetSeconds: Double {
        max(0, positionSeconds - 2.0)
    }

    public init(
        item: PlayableItem,
        positionSeconds: Double,
        durationSeconds: Double,
        updatedAt: Date = Date()
    ) {
        self.id = item.id
        self.item = item
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
    }
}

/// Persists exact-second playback checkpoints to disk so pausing for 10+ minutes or closing the app
/// never loses the user's spot (even if the IPTV server closes the idle stream socket).
@MainActor
public final class WatchProgressStore: ObservableObject {
    @Published public private(set) var records: [String: WatchProgressRecord] = [:]
    public var onDidChange: (() -> Void)?

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let appDir = supportDir.appendingPathComponent("StreamFlixIPTV", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.storageURL = appDir.appendingPathComponent("watch_progress.json")
        }
        load()
    }

    private func seriesDedupeKey(for item: PlayableItem) -> String {
        guard item.kind == .episode else { return item.id }
        if let sid = item.seriesId {
            return "series-\(sid)"
        }
        let baseTitle = item.title.components(separatedBy: " • ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (baseTitle?.isEmpty == false) ? "series-name-\(baseTitle!.lowercased())" : item.id
    }

    public var continueWatchingList: [WatchProgressRecord] {
        let sorted = records.values
            .filter { $0.item.kind != .live && !$0.isCompleted && $0.positionSeconds >= 5 }
            .sorted { $0.updatedAt > $1.updatedAt }

        var seenSeries = Set<String>()
        var unique: [WatchProgressRecord] = []
        for rec in sorted {
            let key = seriesDedupeKey(for: rec.item)
            if seenSeries.insert(key).inserted {
                unique.append(rec)
            }
        }
        return unique
    }

    public func savedPosition(for itemId: String) -> Double? {
        guard let record = records[itemId], !record.isCompleted else { return nil }
        return record.resumeTargetSeconds
    }

    public func updateProgress(item: PlayableItem, position: Double, duration: Double) {
        guard item.kind != .live, duration > 0, position.isFinite, duration.isFinite else { return }
        if item.kind == .episode {
            let targetKey = seriesDedupeKey(for: item)
            let staleKeys = records.keys.filter { key in
                key != item.id && records[key].map { seriesDedupeKey(for: $0.item) == targetKey } == true
            }
            for staleKey in staleKeys {
                records.removeValue(forKey: staleKey)
            }
        }
        let record = WatchProgressRecord(
            item: item,
            positionSeconds: max(0, position),
            durationSeconds: duration,
            updatedAt: Date()
        )
        if record.isCompleted {
            records.removeValue(forKey: item.id)
        } else {
            records[item.id] = record
        }
        persist()
        onDidChange?()
    }

    public func removeProgress(for itemId: String) {
        records.removeValue(forKey: itemId)
        persist()
        onDidChange?()
    }

    public func mergeRemoteRecords(_ remote: [String: WatchProgressRecord]) {
        var changed = false
        for (id, remoteRec) in remote {
            if let localRec = records[id] {
                if remoteRec.updatedAt > localRec.updatedAt {
                    records[id] = remoteRec
                    changed = true
                }
            } else if !remoteRec.isCompleted {
                records[id] = remoteRec
                changed = true
            }
        }
        var newestBySeries: [String: WatchProgressRecord] = [:]
        for rec in records.values where rec.item.kind == .episode {
            let key = seriesDedupeKey(for: rec.item)
            if let existing = newestBySeries[key] {
                if rec.updatedAt > existing.updatedAt {
                    newestBySeries[key] = rec
                }
            } else {
                newestBySeries[key] = rec
            }
        }
        let keepIds = Set(newestBySeries.values.map(\.id))
        let staleEpisodeIds = records.values
            .filter { $0.item.kind == .episode && !keepIds.contains($0.id) }
            .map(\.id)
        for staleId in staleEpisodeIds {
            records.removeValue(forKey: staleId)
            changed = true
        }
        if changed {
            persist()
        }
    }

    public func clearAll() {
        records.removeAll()
        persist()
        onDidChange?()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([String: WatchProgressRecord].self, from: data) else {
            return
        }
        self.records = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
