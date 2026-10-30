import Foundation

/// Appends a small log next to the diagnostic output. Handy when the app runs as
/// a menu bar accessory with nowhere to print.
enum AppLog {
    static let url: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let directory = base.appendingPathComponent("Logs/Konvolusi")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("app.log")
    }()

    private static let formatter = ISO8601DateFormatter()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
