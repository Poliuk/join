import Foundation
import OSLog
import JoinCore

/// How one meeting's alert state is saved, for either kind (`alertStates` for the full-screen alert,
/// `notificationStates` for the notification), so snoozes, dismissals and sent notifications survive a
/// relaunch until the meeting ends.
struct AlertStateRecord: Codable {
    let state: AlertState
    let expiresAt: Date
}

extension UserDefaults {
    /// The value saved as JSON under `key`, or nil when there's none. One that can't be read is logged as
    /// `description` ("the saved pause") and left out.
    func decodedJSON<Value: Decodable>(_ type: Value.Type, forKey key: String, description: String, log: Logger) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("Couldn't read \(description, privacy: .public): \(String(describing: error))")
            return nil
        }
    }

    /// Saves `value` as JSON. One that can't be encoded is logged, and its key removed, so a relaunch doesn't
    /// read an older value back.
    func setJSON(_ value: some Encodable, forKey key: String, log: Logger) {
        do {
            set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            log.error("Couldn't save \(key, privacy: .public): \(String(describing: error))")
            removeObject(forKey: key)
        }
    }
}
