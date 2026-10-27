import Foundation
import Observation
import ZhongmiaoCore

struct NtfySnapshot: Codable, Sendable {
    var topics: [String]
    var selectedTopic: String?
    var messages: [NtfyMessage]
}

@MainActor
@Observable
final class NtfyModel {

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var topics: [String] = []
    private(set) var selectedTopic: String?
    private(set) var messages: [NtfyMessage] = []
    private(set) var searchResults: [NtfyMessage] = []
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    var query = ""
    var expandedID: String?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
    }

    private var client: NtfyClient {
        NtfyClient(baseURL: baseURL, token: center.credential(for: "ntfy")?.bearer)
    }

    func loadCache() async {
        guard topics.isEmpty else { return }
        if let cached = await center.cache.load(NtfySnapshot.self, serviceID: "ntfy") {
            topics = cached.payload.topics
            selectedTopic = cached.payload.selectedTopic
            messages = cached.payload.messages
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
            let fetched = try await client.topics()
            topics = fetched
            if selectedTopic == nil || !fetched.contains(selectedTopic ?? "") {
                selectedTopic = fetched.first
            }
            if let topic = selectedTopic {
                messages = try await client.messages(topic: topic)
            } else {
                messages = []
            }
            lastUpdated = .now
            center.markValid(serviceID: "ntfy")
            await saveCache()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "ntfy")
        }
        isLoading = false
    }

    func selectTopic(_ topic: String) async {
        guard selectedTopic != topic else { return }
        selectedTopic = topic
        query = ""
        searchResults = []
        messages = []
        await loadMessages()
    }

    func loadMessages() async {
        guard let topic = selectedTopic else { return }
        isLoading = true
        error = nil
        do {
            messages = try await client.messages(topic: topic)
            lastUpdated = .now
            center.markValid(serviceID: "ntfy")
            await saveCache()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "ntfy")
        }
        isLoading = false
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            searchResults = try await client.search(query: trimmed)
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
        }
    }

    var visibleMessages: [NtfyMessage] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? messages : searchResults
    }

    func markAllRead() async {
        guard let topic = selectedTopic else { return }
        let ids = messages.compactMap(\.id)
        do {
            try await client.markRead(topic: topic, ids: ids)
            messages = []
            await saveCache()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "ntfy")
        }
    }

    func delete(_ message: NtfyMessage) async {
        guard let topic = message.topic ?? selectedTopic, let id = message.id else { return }
        do {
            try await client.delete(topic: topic, id: id)
            messages.removeAll { $0.id == id }
            searchResults.removeAll { $0.id == id }
            await saveCache()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "ntfy")
        }
    }

    private func saveCache() async {
        let snapshot = NtfySnapshot(
            topics: topics,
            selectedTopic: selectedTopic,
            messages: messages
        )
        await center.cache.save(snapshot, serviceID: "ntfy")
    }
}
