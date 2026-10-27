import Foundation

/// 每应用一份原生快照。失败不清缓存，损坏文件留档。
actor IntegrationCache {

    struct Snapshot<Payload: Codable & Sendable>: Codable, Sendable {
        var fetchedAt: Date
        var payload: Payload
    }

    static let shared = IntegrationCache()

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? Self.standardDirectory()
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func load<Payload: Codable & Sendable>(
        _ type: Payload.Type,
        serviceID: String
    ) -> Snapshot<Payload>? {
        let url = fileURL(serviceID: serviceID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(Snapshot<Payload>.self, from: data)
        } catch {
            quarantine(url)
            return nil
        }
    }

    func save<Payload: Codable & Sendable>(
        _ payload: Payload,
        serviceID: String,
        fetchedAt: Date = .now,
        protect: Bool = false
    ) {
        let snapshot = Snapshot(fetchedAt: fetchedAt, payload: payload)
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        let url = fileURL(serviceID: serviceID)
        try? data.write(to: url, options: .atomic)
        if protect {
            harden(url)
        }
    }

    func remove(serviceID: String) {
        try? FileManager.default.removeItem(at: fileURL(serviceID: serviceID))
    }

    func fileURL(serviceID: String) -> URL {
        let safe = serviceID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character : "-"
        }
        return directory.appendingPathComponent("\(String(safe)).json")
    }

    private func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    private func harden(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static func standardDirectory() -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base
            .appendingPathComponent("Zhongmiao", isDirectory: true)
            .appendingPathComponent("integrations", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
