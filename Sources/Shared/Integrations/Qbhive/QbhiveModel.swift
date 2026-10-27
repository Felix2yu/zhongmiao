import Foundation
import Observation
import ZhongmiaoCore

@MainActor
@Observable
final class QbhiveModel {

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case downloading
        case seeding
        case stopped
        case errored

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "全部"
            case .downloading: "下载中"
            case .seeding: "做种"
            case .stopped: "已停止"
            case .errored: "错误"
            }
        }
    }

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var snapshot: QbhiveSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var busyHashes: Set<String> = []
    var filter: Filter = .all
    var expandedHash: String?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
    }

    private var client: QbhiveClient {
        QbhiveClient(baseURL: baseURL, token: center.credential(for: "qbhive")?.bearer ?? "")
    }

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(QbhiveSnapshot.self, serviceID: "qbhive") {
            snapshot = cached.payload
            lastUpdated = cached.fetchedAt
        }
    }

    func refreshIfNeeded() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 120 { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let stats = client.stats()
            async let torrents = client.torrents()
            let feeds = (try? await client.feeds()) ?? []
            let value = QbhiveSnapshot(
                stats: try? await stats,
                torrents: try await torrents,
                feeds: feeds
            )
            snapshot = value
            lastUpdated = .now
            center.markValid(serviceID: "qbhive")
            await center.cache.save(value, serviceID: "qbhive")
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qbhive")
        }
        isLoading = false
    }

    func perform(_ action: String, on torrent: QbhiveTorrent) async {
        guard !busyHashes.contains(torrent.hash) else { return }
        busyHashes.insert(torrent.hash)
        do {
            try await client.perform(action, hash: torrent.hash)
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qbhive")
        }
        busyHashes.remove(torrent.hash)
    }

    var torrents: [QbhiveTorrent] {
        let all = snapshot?.torrents ?? []
        switch filter {
        case .all: return all
        case .downloading: return all.filter(\.isDownloading)
        case .seeding: return all.filter(\.isSeeding)
        case .stopped: return all.filter(\.isStopped)
        case .errored: return all.filter(\.isErrored)
        }
    }
}
