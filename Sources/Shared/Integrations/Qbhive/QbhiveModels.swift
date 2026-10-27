import Foundation

struct QbhiveStats: Codable, Hashable, Sendable {
    var dlSpeed: Double?
    var upSpeed: Double?
    var dlSpeedLimit: Double?
    var upSpeedLimit: Double?
    var activeCount: Int?
    var downloadingCount: Int?
    var seedingCount: Int?
    var stalledCount: Int?
    var erroredCount: Int?
    var stoppedUP: Int?
    var stoppedDL: Int?
}

struct QbhiveTorrent: Codable, Hashable, Sendable, Identifiable {
    var hash: String
    var name: String
    var state: String?
    var progress: Double?
    var size: Int64?
    var downloaded: Int64?
    var uploaded: Int64?
    var upspeed: Double?
    var dlspeed: Double?
    var category: String?
    var tags: String?
    var addedOn: Int64?
    var completionOn: Int64?
    var ratio: Double?
    var numSeeds: Int?
    var numLeechs: Int?

    var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, name, state, progress, size, downloaded, uploaded, upspeed, dlspeed, category, tags, ratio
        case addedOn = "added_on"
        case completionOn = "completion_on"
        case numSeeds = "num_seeds"
        case numLeechs = "num_leechs"
    }

    var isDownloading: Bool {
        guard let state = state?.lowercased() else { return false }
        return state.contains("dl") || state.contains("download") || state.contains("metadl") || state.contains("stalleddl")
    }

    var isSeeding: Bool {
        guard let state = state?.lowercased() else { return false }
        return state.contains("up") || state.contains("seed")
    }

    var isErrored: Bool {
        state?.lowercased().contains("error") == true
    }

    var isStopped: Bool {
        state?.lowercased().contains("paused") == true || state?.lowercased().contains("stopped") == true
    }
}

struct QbhiveFeed: Codable, Hashable, Sendable, Identifiable {
    var feedId: String?
    var feedName: String?
    var enabled: Bool?
    var lastFetchAt: String?
    var itemCount: Int?
    var matched: Int?
    var downloaded: Int?
    var failed: Int?
    var lastError: String?

    var id: String { feedId ?? feedName ?? lastFetchAt ?? "feed" }
}

struct QbhiveSnapshot: Codable, Sendable {
    var stats: QbhiveStats?
    var torrents: [QbhiveTorrent]
    var feeds: [QbhiveFeed]
}
