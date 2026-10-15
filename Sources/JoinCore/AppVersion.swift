import Foundation

/// A release version, "1.2.3": the app's `CFBundleShortVersionString`, and a release tag without its "v".
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// "1.2.3" or "v1.2.3". Anything else is nil: two or four parts, a pre-release suffix ("1.2.3-beta"),
    /// signs, spaces, or a leading zero ("01.2.3"; a plain "0" is fine).
    public init?(_ string: String) {
        let numbers = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = numbers.split(separator: ".", omittingEmptySubsequences: false).map(Self.number)
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// "1.2.3".
    public var description: String { "\(major).\(minor).\(patch)" }

    /// The release tag, "v1.2.3".
    public var tag: String { "v" + description }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// ASCII digits only, without a leading zero; nil if it doesn't fit an Int.
    private static func number(_ part: Substring) -> Int? {
        guard !part.isEmpty,
              part.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              part == "0" || !part.hasPrefix("0")
        else { return nil }
        return Int(part)
    }
}

/// Stored as its "1.2.3" string, the shape preferences have always held it in. Decoding throws on a string
/// `init?(_:)` refuses, so a version that can't be read never loads as some other one.
extension AppVersion: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = AppVersion(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a version: \(string)")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
