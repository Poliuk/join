import AppKit

/// Writes a PNG of every visible window of the app, for checking UI without screen-recording access.
/// Driven by the `com.poliuk.join.snapshot` script hook; the argument is the output folder.
@MainActor
enum WindowSnapshots {
    static func write(to directory: String) {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let kind = String(describing: type(of: window))
            let title = window.title.isEmpty ? "" : "-" + window.title.replacingOccurrences(of: "/", with: "-")
            let name = String(format: "%02d-%@%@.png", index, kind, title)
            try? data.write(to: folder.appendingPathComponent(name))
        }
    }
}
