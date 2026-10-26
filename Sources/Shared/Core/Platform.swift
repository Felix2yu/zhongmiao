import Foundation
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 平台差异的收敛点。新增平台时只需要补这一层。
enum Platform {

    @MainActor
    static func openExternally(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    @MainActor
    static func haptic(_ style: String) {
        #if os(iOS)
        switch style {
        case "success":
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning":
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "heavy":
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "medium":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    @MainActor
    static var deviceName: String {
        #if os(iOS)
        UIDevice.current.name
        #elseif os(macOS)
        Host.current().localizedName ?? "Mac"
        #endif
    }

    static var platformName: String {
        #if os(iOS)
        "ios"
        #elseif os(macOS)
        "macos"
        #endif
    }

    /// 下载文件落盘目录。
    static func downloadsDirectory() -> URL {
        let manager = FileManager.default
        #if os(iOS)
        let base = manager.urls(for: .documentDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("下载", isDirectory: true)
        #else
        let base = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("众妙", isDirectory: true)
        #endif
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// 生成不冲突的文件名，避免覆盖已有下载。
    static func uniqueFileURL(in directory: URL, suggestedName: String) -> URL {
        let sanitized = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = sanitized.isEmpty ? "下载" : sanitized
        var candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        repeat {
            let filename = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(filename)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path) && index < 1000
        return candidate
    }
}
