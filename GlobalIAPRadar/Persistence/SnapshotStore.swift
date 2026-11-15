import Foundation

/// Local persistence for favourites, recent searches and price snapshots.
///
/// JSON files in Application Support are used on purpose: the data volume is
/// small (a few thousand rows), it keeps the app dependency-free, and it avoids
/// the SwiftData macro pitfalls on a 4 GB device.
actor SnapshotStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("GlobalIAPRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Snapshots

    func loadSnapshots() -> [PriceSnapshot] {
        read([PriceSnapshot].self, from: "snapshots.json") ?? []
    }

    func saveSnapshots(_ snapshots: [PriceSnapshot]) {
        write(snapshots, to: "snapshots.json")
    }

    /// Appends snapshots, keeping one row per app/product/storefront/day.
    func mergeSnapshots(_ incoming: [PriceSnapshot]) -> [PriceSnapshot] {
        var existing = loadSnapshots()
        let calendar = Calendar.current
        var index: [String: Int] = [:]
        for (offset, snapshot) in existing.enumerated() {
            index[key(for: snapshot, calendar: calendar), default: offset]
        }
        for snapshot in incoming {
            let key = key(for: snapshot, calendar: calendar)
            if let offset = index[key] {
                existing[offset] = snapshot
            } else {
                index[key] = existing.count
                existing.append(snapshot)
            }
        }
        existing.sort { $0.capturedAt > $1.capturedAt }
        if existing.count > 20_000 {
            existing = Array(existing.prefix(20_000))
        }
        saveSnapshots(existing)
        return existing
    }

    private func key(for snapshot: PriceSnapshot, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: snapshot.capturedAt)
        let dayKey = Int(day.timeIntervalSince1970)
        return "\(snapshot.appID)|\(snapshot.productID)|\(snapshot.storefront)|\(dayKey)"
    }

    // MARK: Favourites

    func loadFavorites() -> [Favorite] {
        read([Favorite].self, from: "favorites.json") ?? []
    }

    func saveFavorites(_ favorites: [Favorite]) {
        write(favorites, to: "favorites.json")
    }

    // MARK: Recent searches

    func loadRecentSearches() -> [String] {
        read([String].self, from: "recent.json") ?? []
    }

    func saveRecentSearches(_ terms: [String]) {
        write(terms, to: "recent.json")
    }

    // MARK: Cache management

    func clearCache() {
        for name in ["snapshots.json", "favorites.json", "recent.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func cacheSizeInBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                         includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    // MARK: IO

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) {
        let url = directory.appendingPathComponent(name)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
