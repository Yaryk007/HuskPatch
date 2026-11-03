import SwiftUI

/// The system log shown in the Lab panel. Anything can write to it with `OSLogger.shared.log(...)`.
final class OSLogger: ObservableObject {
    static let shared = OSLogger()

    enum Level: String, CaseIterable {
        case debug, info, warn, error

        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warn: return .orange
            case .error: return .red
            }
        }

        var letter: String { String(rawValue.prefix(1)).uppercased() }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let tag: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let limit = 800
    private let started = Date()

    private init() {
        entries.append(Entry(date: Date(), level: .info, tag: "Kernel", message: "ModemOS booting"))
    }

    func log(_ tag: String, _ message: String, level: Level = .info) {
        let entry = Entry(date: Date(), level: level, tag: tag, message: message)
        // Never publish from inside a view update.
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.limit {
                self.entries.removeFirst(self.entries.count - self.limit)
            }
        }
    }

    func clear() {
        entries.removeAll()
        log("Logs", "Cleared")
    }

    /// The whole log as plain text (for copying).
    var text: String {
        entries.map { entry in
            "\(Self.timeString(entry.date)) \(entry.level.letter) [\(entry.tag)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
