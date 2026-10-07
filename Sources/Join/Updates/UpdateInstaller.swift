import CryptoKit
import Foundation
import OSLog
import Security
import JoinCore

private let logger = Logger(subsystem: "com.poliuk.join", category: "updates")

/// Installs an update: downloads Join.zip, checks it against the release's digest, unzips it with ditto,
/// checks the app inside (bundle identifier, version, minimum macOS, processor, code signature), then swaps
/// it in for the running copy and relaunches. When the running copy can't be swapped (translocated,
/// read-only, or the swap fails), the new copy goes to a folder of its own in `revealFolder` for the user to
/// drag to Applications. It all runs off the main actor, in a working folder that is removed at the end.
struct UpdateInstaller: Sendable {
    enum Outcome: Equatable, Sendable {
        /// The new copy is in place, and a helper opens it once this process has quit.
        case relaunching
        /// The new copy, waiting to be dragged to Applications.
        case revealed(URL)
    }

    /// What the new copy's code signature must satisfy. Releases are signed ad hoc, so the identifier is
    /// all there is to check: the trust is in HTTPS and the project's GitHub releases.
    static let signingRequirement = #"identifier "com.poliuk.join""#

    let update: AvailableUpdate
    /// The running app, which the new copy replaces.
    var target = Bundle.main.bundleURL
    /// The bundle identifier the new copy must have: the running app's.
    var bundleIdentifier = Bundle.main.bundleIdentifier
    /// Where a copy that can't replace the running one goes: ~/Downloads, or a temporary folder in fixture runs.
    let revealFolder: URL
    /// `open --env` variables for the relaunched copy, so a fixture run comes back as one.
    var relaunchEnvironment: [String: String] = [:]
    let userAgent: String

    /// `report` gets the download's progress, then `.installing` once it's downloaded.
    func run(report: @escaping @Sendable (UpdateInstallState) -> Void) async throws -> Outcome {
        let fileManager = FileManager.default
        let work = try Self.workFolder(for: target)
        let archive = work.appendingPathComponent(UpdateCheck.assetName)
        // The archive on its own first: removing the folder stops at anything of an old copy that can't be
        // deleted (see replaceTarget).
        defer {
            try? fileManager.removeItem(at: archive)
            try? fileManager.removeItem(at: work)
        }

        try await Download.run(from: update.downloadURL, to: archive, userAgent: userAgent) { report(.downloading($0)) }
        report(.installing)
        if let expected = update.sha256 {
            guard (try? Self.sha256(of: archive)) == expected else { throw UpdateFailure.checksum }
        }
        let unzipped = work.appendingPathComponent("Unzipped", isDirectory: true)
        try await Self.unzip(archive, into: unzipped)
        let app = unzipped.appendingPathComponent("Join.app", isDirectory: true)
        try verify(app)

        if let installed = replaceTarget(with: app) {
            try Self.relaunch(installed, environment: relaunchEnvironment)
            return .relaunching
        }
        // A swap that failed part way may have left something else at `app`: only a copy that still
        // passes the checks is revealed.
        guard (try? verify(app)) != nil else { throw UpdateFailure.save }
        return .revealed(try reveal(app))
    }

    // MARK: Working folder

    /// An item-replacement folder on the running app's volume, so the swap is a rename; a temporary folder
    /// when there's none (a read-only volume, a translocated app).
    private static func workFolder(for target: URL) throws -> URL {
        let fileManager = FileManager.default
        if let folder = try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true) {
            return folder
        }
        let folder = fileManager.temporaryDirectory.appendingPathComponent("JoinUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw UpdateFailure.save
        }
        return folder
    }

    // MARK: Checks

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `ditto -x -k`, the counterpart of the release's `ditto -c -k --keepParent`.
    private static func unzip(_ archive: URL, into folder: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UpdateFailure.unzip)
            }
        }
        guard status == 0 else { throw UpdateFailure.unzip }
    }

    /// `app` must be a real folder holding Join! at the update's version that can run on this Mac (its
    /// macOS and its processor), validly signed in every architecture and every piece of nested code.
    private func verify(_ app: URL) throws {
        let values = try? app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink == false,
              let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let bundleIdentifier, info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == update.version.description
        else { throw UpdateFailure.notJoin }
        if let minimum = info["LSMinimumSystemVersion"] as? String, !Self.systemIsAtLeast(minimum) {
            throw UpdateFailure.unsupportedSystem(minimum)
        }
        guard Self.hasCodeForThisProcessor(app) else { throw UpdateFailure.wrongArchitecture }

        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(Self.signingRequirement as CFString, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateFailure.signature }
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode))
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            logger.error("The downloaded app's signature failed validation: \(status, privacy: .public)")
            throw UpdateFailure.signature
        }
    }

    /// "14.0" against the running macOS. One that can't be read doesn't stop the install.
    static func systemIsAtLeast(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return true }
        let numbers = parts.compactMap { $0 } + [0, 0]
        let version = OperatingSystemVersion(majorVersion: numbers[0], minorVersion: numbers[1], patchVersion: numbers[2])
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(version)
    }

    /// Whether the app's executable has a slice for the processor this copy runs on. Signature checks
    /// only cover the slices that are there, so an arm64-only build would otherwise pass on an Intel Mac
    /// and replace a copy that runs with one that can't.
    private static func hasCodeForThisProcessor(_ app: URL) -> Bool {
        #if arch(arm64)
        let architecture = NSBundleExecutableArchitectureARM64
        #else
        let architecture = NSBundleExecutableArchitectureX86_64
        #endif
        return Bundle(url: app)?.executableArchitectures?.contains { $0.intValue == architecture } == true
    }

    // MARK: Replace or reveal

    /// False when the running copy can't be swapped in place: translocated (opened where it was downloaded,
    /// so macOS runs a read-only copy), on a read-only volume, or in a folder the user can't write to.
    private static func canReplace(_ target: URL) -> Bool {
        let fileManager = FileManager.default
        return target.pathExtension == "app"
            && !target.path.contains("/AppTranslocation/")
            && fileManager.isWritableFile(atPath: target.path)
            && fileManager.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    /// Swaps the new copy in for the running one in one step; nil when it can't. `replaceItemAt` can throw
    /// after the swap, when the old copy (by then at `app`) can't be deleted: if the target passes the
    /// checks, the new copy is in place and that counts as installed.
    private func replaceTarget(with app: URL) -> URL? {
        guard Self.canReplace(target) else { return nil }
        do {
            // The new copy's metadata only, so nothing of the old copy's (its own download's quarantine
            // flag, say) carries over.
            return try FileManager.default.replaceItemAt(target, withItemAt: app, backupItemName: nil, options: .usingNewMetadataOnly)
                ?? target
        } catch {
            guard (try? verify(target)) != nil else {
                logger.error("Couldn't replace the running copy: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            logger.error("Replaced the running copy, but couldn't delete the old one: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: app)
            return target
        }
    }

    /// Moves the new copy to "Join 1.1.0/Join.app" in `revealFolder`, or "Join 1.1.0 2/Join.app" and so on
    /// when that folder is taken.
    private func reveal(_ app: URL) throws -> URL {
        let fileManager = FileManager.default
        let name = "Join \(update.version)"
        do {
            try fileManager.createDirectory(at: revealFolder, withIntermediateDirectories: true)
            guard let folder = (1...100).lazy
                .map({ revealFolder.appendingPathComponent($0 == 1 ? name : "\(name) \($0)", isDirectory: true) })
                .first(where: { !fileManager.fileExists(atPath: $0.path) })
            else { throw UpdateFailure.save }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            let destination = folder.appendingPathComponent(app.lastPathComponent, isDirectory: true)
            try fileManager.moveItem(at: app, to: destination)
            return destination
        } catch {
            logger.error("Couldn't move the new copy to \(revealFolder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw UpdateFailure.save
        }
    }

    // MARK: Relaunch

    /// Starts a shell that waits for this process to exit, then opens `app` as a new instance (`-n`: another
    /// copy with the same identifier may be running, on a developer's Mac). It gets a session of its own,
    /// so it outlives the app instead of going down with its process group, and no open files but
    /// /dev/null.
    private static func relaunch(_ app: URL, environment: [String: String]) throws {
        let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; shift; exec /usr/bin/open -n "$@""#
        var arguments = ["/bin/sh", "-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier)]
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            arguments += ["--env", "\(key)=\(value)"]
        }
        arguments.append(app.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, envp)
        guard result == 0 else {
            logger.error("Couldn't start the relaunch helper: \(result, privacy: .public)")
            throw UpdateFailure.relaunch
        }
    }
}

/// One URLSession data task streamed into `destination`, so nothing lands outside the working folder. The
/// answer must be a 200 (after any redirects); progress is reported as it passes each whole percent; and the
/// download stops as soon as it's known to be more than `UpdateCheck.maximumDownloadSize`. Its state is
/// only touched on the session's serial delegate queue.
private final class Download: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Gives up after this long in all, or after 20 s without data.
    static let timeout: TimeInterval = 10 * 60

    private let destination: URL
    private let progress: @Sendable (Double?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    /// Open from a 200 answer until the task completes.
    private var file: FileHandle?
    private var failure: UpdateFailure?
    private var received: Int64 = 0
    /// From the Content-Length, or -1 without one.
    private var expected: Int64 = -1
    private var reportedPercent: Int?

    private init(destination: URL, progress: @escaping @Sendable (Double?) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func run(from url: URL, to destination: URL, userAgent: String,
                    progress: @escaping @Sendable (Double?) -> Void) async throws {
        let download = Download(destination: destination, progress: progress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .updates(total: timeout), delegate: download, delegateQueue: queue)
        // The session holds its delegate until it's invalidated.
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // A fixed language, so the request doesn't carry the user's.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let task = session.dataTask(with: request)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.addOperation {
                download.continuation = continuation
                task.resume()
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            failure = .download
            completionHandler(.cancel)
            return
        }
        expected = response.expectedContentLength
        guard expected <= Int64(UpdateCheck.maximumDownloadSize) else {
            failure = .tooLarge
            completionHandler(.cancel)
            return
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let file = try? FileHandle(forWritingTo: destination)
        else {
            failure = .download
            completionHandler(.cancel)
            return
        }
        self.file = file
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let file else { return }
        received += Int64(data.count)
        guard received <= Int64(UpdateCheck.maximumDownloadSize) else {
            failure = .tooLarge
            dataTask.cancel()
            return
        }
        do {
            try file.write(contentsOf: data)
        } catch {
            failure = .download
            dataTask.cancel()
            return
        }
        // The size is unknown without a Content-Length; the bar then shows no percent.
        guard expected > 0 else { return }
        let fraction = min(Double(received) / Double(expected), 1)
        let percent = Int(fraction * 100)
        guard percent != reportedPercent else { return }
        reportedPercent = percent
        progress(fraction)
    }

    /// Called once for the task, however it ends, so the continuation resumes here and only here.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let wasSaving = file != nil
        do {
            try file?.close()
        } catch {
            failure = failure ?? .download
        }
        file = nil
        if let error, failure == nil {
            logger.error("The download failed: \(error.localizedDescription, privacy: .public)")
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else if error == nil, wasSaving {
            continuation?.resume()
        } else {
            continuation?.resume(throwing: UpdateFailure.download)
        }
        continuation = nil
    }
}
