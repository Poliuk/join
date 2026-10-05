import AppKit

enum SystemSounds {
    /// Names of the sounds shipped with macOS, usable with `NSSound(named:)`.
    static let names: [String] = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["aiff", "aif", "caf", "wav"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    static func sound(named name: String?) -> NSSound? {
        guard let name else { return nil }
        return NSSound(named: NSSound.Name(name))
    }
}
