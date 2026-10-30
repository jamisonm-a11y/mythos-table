import AppKit
import Foundation

/// Memory + disk cache for card images fetched from arkhamdb.com.
actor ImageCache {
    static let shared = ImageCache()

    private var memory: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    func image(for path: String) async -> NSImage? {
        if let cached = memory[path] { return cached }
        if let task = inflight[path] { return await task.value }

        let task = Task<NSImage?, Never> {
            let file = Storage.imagesDir.appendingPathComponent(Self.fileName(for: path))
            if let image = NSImage(contentsOf: file) { return image }
            guard let url = ArkhamDB.imageURL(path),
                  let data = try? await ArkhamDB.get(url),
                  let image = NSImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return image
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image { memory[path] = image }
        return image
    }

    static func fileName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path.replacingOccurrences(of: "/", with: "_") : name
    }

    func clearMemory() { memory.removeAll() }
}
