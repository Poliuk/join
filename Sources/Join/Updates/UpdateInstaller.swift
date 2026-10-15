import CryptoKit
import Foundation
import OSLog
import Security
import JoinCore

private let logger = Logger(subsystem: "com.poliuk.join", category: "updates")

/// The two steps of installing an update, so that nothing quits before the user says so: `prepare` when
/// the user clicks Install, `install` when they click Install and Relaunch. `UpdateInstaller` does the real
/// work; `FixtureUpdateInstaller` stands in for it in a fixture run with JOIN_FIXTURE_UPDATE=ready.
protocol UpdateInstalling: Sendable {
    /// Downloads and verifies the update; `report` gets the download's progress, then `.verifying`. The new
    /// copy then waits, ready for `install`. A failure leaves nothing behind.
    func prepare(report: @escaping @Sendable (UpdateInstallState) -> Void) async throws
    /// Whether the copy `prepare` left is still there, with its files.
    var hasReadyCopy: Bool { get }
    /// Puts the ready copy in place and starts the helper that opens it once Join! has quit, or reveals it
    /// when it can't replace the running one. Throws `ReadyCopyDamaged` when the copy no longer passes the
    /// checks before anything is replaced. Whatever happens, nothing of the download is left but a revealed
    /// copy.
    func install() async throws -> UpdateInstaller.Outcome
    /// Removes the download, ready or still under way: an update that's no longer on offer, or Join!
    /// quitting without Install and Relaunch.
    func discard()
}

/// `install()` found the ready copy no longer passes the checks, before replacing anything: damaged while it
/// waited (some of its files deleted, say). Nothing was touched and the copy is gone, so the update goes back
/// to Install, which downloads it again, rather than failing.
struct ReadyCopyDamaged: Error {
    /// What the check found.
    let reason: any Error
}

/// Installs an update in the two steps of `UpdateInstalling`, in a working folder made when it's created.
/// `prepare` downloads Join.zip, checks it against the release's digest, unzips it with ditto and checks the
/// app inside (bundle identifier, version, minimum macOS, processor, code signature); the new copy then
/// waits in the working folder. `install` checks that copy again, since it may have waited for hours, swaps
/// it in for the running copy and relaunches. When the running copy can't be swapped (translocated,
/// read-only, or the swap fails), the new copy goes to a folder of its own in `revealFolder` for the user to
/// drag to Applications. Both steps run off the main actor. The working folder is removed when a step fails,
/// when `install` ends and by `discard`, and one a crash left behind by `removeLeftovers` at a later launch.
struct UpdateInstaller: UpdateInstalling {
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
    let target: URL
    /// The bundle identifier the new copy must have: the running app's.
    let bundleIdentifier: String?
    /// Where a copy that can't replace the running one goes: ~/Downloads, or a temporary folder in fixture runs.
    let revealFolder: URL
    /// `open --env` variables for the relaunched copy, so a fixture run comes back as one.
    let relaunchEnvironment: [String: String]
    let userAgent: String
    /// The working folder, where the download and the ready copy live (`workFolder(for:)`).
    let work: URL

    /// Makes the working folder; fails with `save` when it can't.
    init(
        update: AvailableUpdate,
        revealFolder: URL,
        relaunchEnvironment: [String: String] = [:],
        userAgent: String,
        target: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws {
        self.update = update
        self.revealFolder = revealFolder
        self.relaunchEnvironment = relaunchEnvironment
        self.userAgent = userAgent
        self.target = target
        self.bundleIdentifier = bundleIdentifier
        work = try Self.workFolder(for: target)
    }

    private var archive: URL { work.appendingPathComponent(UpdateCheck.assetName) }
    /// The new copy, once unzipped.
    private var app: URL { work.appendingPathComponent("Unzipped/Join.app", isDirectory: true) }

    func prepare(report: @escaping @Sendable (UpdateInstallState) -> Void) async throws {
        do {
            try await Download.run(from: update.downloadURL, to: archive, userAgent: userAgent) { report(.downloading($0)) }
            report(.verifying)
            if let expected = update.sha256 {
                guard (try? Self.sha256(of: archive)) == expected else { throw UpdateFailure.checksum }
            }
            try await Self.unzip(archive, into: app.deletingLastPathComponent())
            try verify(app)
        } catch {
            discard()
            throw error
        }
        // Only the app waits for Install and Relaunch.
        try? FileManager.default.removeItem(at: archive)
    }

    /// The app's Info.plist and the executable it names are still files, not only the folders: files can be
    /// deleted from a copy that waited while its folders stay.
    var hasReadyCopy: Bool {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        guard let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty, !executable.contains("/")
        else { return false }
        let values = try? contents.appendingPathComponent("MacOS/\(executable)").resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    func install() async throws -> Outcome {
        defer { discard() }
        // The copy may have waited for days in a folder this user can write to: it must still pass. One that
        // doesn't was damaged while it waited, and nothing has been replaced yet.
        do {
            try verify(app)
        } catch {
            throw ReadyCopyDamaged(reason: error)
        }
        if let installed = replaceTarget(with: app) {
            try Self.relaunch(installed, environment: relaunchEnvironment)
            return .relaunching
        }
        // A swap that failed part way may have left something else at `app`: only a copy that still
        // passes the checks is revealed.
        guard (try? verify(app)) != nil else { throw UpdateFailure.save }
        return .revealed(try reveal(app))
    }

    /// The archive on its own first: removing the folder stops at anything of an old copy that can't be
    /// deleted (see replaceTarget).
    func discard() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: archive)
        try? fileManager.removeItem(at: work)
    }

    // MARK: Working folder

    /// Where working folders go first: ~/Library/Application Support/com.poliuk.join/Updates.noindex. Not the
    /// temporary folder, where a ready copy would wait for days: macOS deletes the files there that are more
    /// than three days old, and an unzipped copy's files are as old as the release from the start, since
    /// ditto keeps the archive's dates. ".noindex" keeps Spotlight from indexing the waiting copy as a second
    /// Join!.
    static var updatesFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.poliuk.join", isDirectory: true)
            .appendingPathComponent("Updates.noindex", isDirectory: true)
    }

    /// Working folders in `updatesFolder` are "Update-<process id>-<UUID>", so `removeLeftovers` can tell
    /// which ones a process still running may be using.
    private static let workFolderPrefix = "Update-"

    /// A folder of its own in `updatesFolder`, when that's on the running app's volume, so the swap is a
    /// rename, or when the running app can't be swapped anyway (translocated, say), so the copy will be
    /// revealed. Otherwise an item-replacement folder on the app's volume, or a temporary folder when there's
    /// none (a read-only volume).
    private static func workFolder(for target: URL) throws -> URL {
        let fileManager = FileManager.default
        if let updates = updatesFolder, (try? fileManager.createDirectory(at: updates, withIntermediateDirectories: true)) != nil,
           !canReplace(target) || isOnSameVolume(updates, target.deletingLastPathComponent()) {
            let name = "\(workFolderPrefix)\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
            let folder = updates.appendingPathComponent(name, isDirectory: true)
            if (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: false)) != nil {
                return folder
            }
        }
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

    private static func isOnSameVolume(_ first: URL, _ second: URL) -> Bool {
        guard let one = try? first.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let other = try? second.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return false }
        return one.isEqual(other)
    }

    /// Removes the working folders in `updatesFolder` whose process isn't running any more: a crash or a force
    /// quit skips the discard at quit, and nothing else cleans that folder. One whose process is running is
    /// kept, as it may hold a ready copy: this process's own, or another copy's (a fixture run next to the
    /// real app, say). Run at launch, off the main actor.
    static func removeLeftovers() {
        let fileManager = FileManager.default
        guard let updates = updatesFolder, let names = try? fileManager.contentsOfDirectory(atPath: updates.path) else { return }
        for name in names where name.hasPrefix(workFolderPrefix) {
            guard let pid = pid_t(name.dropFirst(workFolderPrefix.count).prefix(while: { $0 != "-" })), pid > 0,
                  kill(pid, 0) != 0, errno == ESRCH
            else { continue }
            logger.notice("Removing a download left by process \(pid, privacy: .public)")
            try? fileManager.removeItem(at: updates.appendingPathComponent(name, isDirectory: true))
        }
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
    static func relaunch(_ app: URL, environment: [String: String]) throws {
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

/// Install in a fixture run with JOIN_FIXTURE_UPDATE=ready, so the ready state can be seen without the
/// network: a pretend download of about three seconds and a pretend check, then a ready copy that isn't
/// there. Install and Relaunch relaunches the fixture as it is, through the same helper as a real install,
/// and replaces nothing. Nothing touches the network or the disk.
struct FixtureUpdateInstaller: UpdateInstalling {
    /// `open --env` variables for the relaunched copy, so it comes back as the same fixture.
    let relaunchEnvironment: [String: String]

    func prepare(report: @escaping @Sendable (UpdateInstallState) -> Void) async throws {
        for step in 0...10 {
            report(.downloading(Double(step) / 10))
            try await Task.sleep(for: .milliseconds(250))
        }
        report(.verifying)
        try await Task.sleep(for: .seconds(1))
    }

    var hasReadyCopy: Bool { true }

    func install() async throws -> UpdateInstaller.Outcome {
        // A `swift run` build has no bundle to open again.
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { throw UpdateFailure.relaunch }
        try UpdateInstaller.relaunch(app, environment: relaunchEnvironment)
        return .relaunching
    }

    func discard() {}
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
