import AppKit

/// Writes a PNG of every visible window of the app, for checking UI without screen-recording access.
/// Driven by the fixture-only `snapshot` script hook. Files always go under
/// `$TMPDIR/JoinSnapshots/<name>`; the name is reduced to a single safe path component.
@MainActor
enum WindowSnapshots {
    static var root: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("JoinSnapshots", isDirectory: true)
    }

    static func write(named name: String?) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String((name ?? "").unicodeScalars.filter { allowed.contains($0) }.map(Character.init))
        let folderName = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "latest" : cleaned
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let kind = String(describing: type(of: window))
            let title = window.title.isEmpty ? "" : "-" + window.title.replacingOccurrences(of: "/", with: "-")
            let fileName = String(format: "%02d-%@%@.png", index, kind, title)
            try? data.write(to: folder.appendingPathComponent(fileName))
        }
    }
}
