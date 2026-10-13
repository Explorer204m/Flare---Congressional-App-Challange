import Foundation

/// Saves the Medical ID as one JSON file in Application Support, with iOS "complete"
/// file protection (encrypted whenever the phone is locked). It never leaves the phone:
/// there is no network code here.
///
/// If a saved file exists but can't be read, it is never overwritten silently: the
/// unreadable file is kept next to it (renamed) before a new Medical ID is saved.
@MainActor
final class MedicalIDStore: ObservableObject {
    @Published private(set) var medicalID = MedicalID()
    /// A saved file exists but could not be read.
    @Published private(set) var loadFailed = false
    @Published var saveErrorMessage: String?

    private let fileURL: URL

    init(directory: URL? = nil) {
        let folder: URL
        if let directory {
            folder = directory
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            folder = support.appendingPathComponent("Flare", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("medical-id.json")
        load()
    }

    var hasContent: Bool { !medicalID.isEmpty }

    // MARK: Load

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            medicalID = MedicalID()
            loadFailed = false
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            medicalID = try decoder.decode(MedicalID.self, from: data)
            loadFailed = false
        } catch {
            medicalID = MedicalID()
            loadFailed = true
        }
    }

    /// Retry reading (for example after the phone was unlocked for the first time).
    func reload() { load() }

    // MARK: Save

    /// Returns true when the Medical ID was written to disk.
    @discardableResult
    func save(_ newValue: MedicalID) -> Bool {
        var value = newValue.cleaned()
        value.updatedAt = Date()
        do {
            if loadFailed { try keepUnreadableCopy() }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            medicalID = value
            loadFailed = false
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = "Your Medical ID could not be saved. Nothing was changed."
            return false
        }
    }

    /// Deletes the saved Medical ID from this phone.
    @discardableResult
    func erase() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            medicalID = MedicalID()
            loadFailed = false
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = "Your Medical ID could not be deleted."
            return false
        }
    }

    private func keepUnreadableCopy() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("medical-id.unreadable-\(stamp).json")
        try FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
