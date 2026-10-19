// Offline emergency database access.
//
// Adapted from `database/ios/EmergencyDatabase.swift` in this project's database
// package (release 2026.10.10.x). Differences from that sample:
//  - lookup returns typed `ContactRow` values instead of string dictionaries
//  - `areas()` and `metadata()` added for location matching and the area picker
//  - startup recovers from a bad working copy using previous -> bundled seed
//  - a newer bundled seed replaces an older working copy (app updates ship new data)
//  - startup fully validates the working copy once and keeps its metadata; the bundled
//    seed is only fully validated when its release date says it would replace it
//  - the "date must not be in the future" clock check is removed from validation:
//    a phone with a wrong clock must never lock someone out of emergency numbers.
//
// All SQLite connections belong to this actor. Never share handles outside it.
import Foundation
import SQLite3
import CryptoKit
import Darwin

enum EmergencyDatabaseError: Error {
    case sqlite(String)
    case invalidRelease(String)
    case replacement(Int32)
}

actor EmergencyDatabase {
    private var db: OpaquePointer?
    private let working: URL
    private let previous: URL
    /// Metadata of the working copy, from the validation that last accepted it.
    private var workingMetadata: [String: String]
    private static let applicationID = "1397707521"

    init(bundleURL: URL) throws {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Flare", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        working = folder.appendingPathComponent("emergency.sqlite")
        previous = folder.appendingPathComponent("emergency.previous.sqlite")

        // 1. Make sure a valid working copy exists. The working copy is fully validated on
        //    every launch (an unchanged release date doesn't prove the file is intact), but
        //    only once: its metadata is kept for step 2 instead of validating it again.
        var current: [String: String]
        if fm.fileExists(atPath: working.path), let validated = try? Self.validate(working) {
            current = validated
        } else {
            current = try Self.restoreWorking(from: [previous, bundleURL], to: working)
        }

        // 2. A newer bundled seed (from an app update) replaces an older working copy.
        //    Reading the bundled release date is cheap and decides whether an update is needed;
        //    the bundled file is fully validated only when it is actually going to be installed.
        if let bundledDate = Self.publishedAt(of: bundleURL),
           let currentDate = current["published_at"],
           bundledDate > currentDate,
           let bundled = try? Self.validate(bundleURL),
           let validatedDate = bundled["published_at"],
           validatedDate > currentDate {
            try Self.atomicCopy(working, to: previous)
            try Self.atomicCopy(bundleURL, to: working)
            current = bundled
        }
        workingMetadata = current

        try Self.markRebuildable(working)
        db = try Self.open(working)
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: Queries

    /// Active contacts for an area and all of its ancestors (see lookup.sql).
    /// When `category` is police, fire or medical, general emergency numbers are included.
    func lookup(areaID: Int64, category: ServiceCategory? = nil) throws -> [ContactRow] {
        guard let db else { throw EmergencyDatabaseError.sqlite("Database closed") }
        let sql = """
        WITH RECURSIVE coverage(id) AS (
          SELECT id FROM areas WHERE id=?1
          UNION SELECT a.parent_id FROM areas a JOIN coverage x ON a.id=x.id
          WHERE a.parent_id IS NOT NULL
        )
        SELECT s.id AS service_id,s.name,s.category,s.description,
               a.id AS coverage_area_id,a.name AS coverage_name,a.type AS coverage_type,
               a.country_code,c.id AS contact_id,c.channel,c.value,c.notes,c.availability,
               (SELECT max(v.checked_at) FROM verifications v
                WHERE v.contact_id=c.id AND v.result='confirmed') AS last_confirmed_at
        FROM coverage x JOIN areas a ON a.id=x.id
        JOIN services s ON s.area_id=a.id AND s.status='active'
        JOIN contacts c ON c.service_id=s.id AND c.status='active'
        WHERE (?2 IS NULL OR s.category=?2 OR
               (?2 IN ('police','fire','medical') AND s.category='general_emergency'))
        ORDER BY CASE WHEN a.id=?1 THEN 0 ELSE 1 END,
                 CASE WHEN s.category='general_emergency' THEN 0 ELSE 1 END,
                 a.name,s.name,c.channel,c.id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Self.sqlError(db) }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, areaID) == SQLITE_OK else { throw Self.sqlError(db) }
        if let category {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let bound = category.rawValue.withCString { pointer in
                sqlite3_bind_text(statement, 2, pointer, -1, transient)
            }
            guard bound == SQLITE_OK else { throw Self.sqlError(db) }
        } else {
            sqlite3_bind_null(statement, 2)
        }

        var rows: [ContactRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw Self.sqlError(db) }
            guard let channel = ContactChannel(rawValue: Self.text(statement, 9) ?? ""),
                  let value = Self.text(statement, 10), !value.isEmpty else { continue }
            rows.append(ContactRow(
                serviceID: sqlite3_column_int64(statement, 0),
                serviceName: Self.text(statement, 1) ?? "",
                category: ServiceCategory(rawValue: Self.text(statement, 2) ?? "") ?? .other,
                serviceDescription: Self.text(statement, 3),
                coverageAreaID: sqlite3_column_int64(statement, 4),
                coverageName: Self.text(statement, 5) ?? "",
                coverageType: AreaType(rawValue: Self.text(statement, 6) ?? "") ?? .country,
                countryCode: Self.text(statement, 7) ?? "",
                contactID: sqlite3_column_int64(statement, 8),
                channel: channel,
                value: value,
                notes: Self.text(statement, 11),
                availability: Self.text(statement, 12),
                lastConfirmedAt: Self.text(statement, 13)
            ))
        }
        return rows
    }

    /// Every area in the dataset (countries, territories, regions, cities).
    func areas() throws -> [Area] {
        guard let db else { throw EmergencyDatabaseError.sqlite("Database closed") }
        let sql = "SELECT id,parent_id,name,type,country_code FROM areas ORDER BY name COLLATE NOCASE,id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Self.sqlError(db) }
        defer { sqlite3_finalize(statement) }

        var result: [Area] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw Self.sqlError(db) }
            guard let name = Self.text(statement, 2),
                  let type = AreaType(rawValue: Self.text(statement, 3) ?? ""),
                  let code = Self.text(statement, 4) else { continue }
            let parent: Int64? = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 1)
            result.append(Area(id: sqlite3_column_int64(statement, 0),
                               parentID: parent, name: name, type: type, countryCode: code))
        }
        return result
    }

    func metadata() throws -> [String: String] {
        guard let db else { throw EmergencyDatabaseError.sqlite("Database closed") }
        var metadata: [String: String] = [:]
        for pair in try Self.strings(db, "SELECT key,value FROM metadata") where pair.count == 2 {
            metadata[pair[0]] = pair[1]
        }
        return metadata
    }

    // MARK: Whole-file update (not used yet; kept from the database package)

    // trustedSHA256 must come from a bundle-pinned digest or an authenticated
    // release manifest. A hash fetched beside an untrusted download is insufficient.
    // Download using URLSession outside this actor; call this once download ends.
    // This method has NO await points: lookup/replace cannot overlap in this actor.
    func install(downloadedURL: URL, trustedSHA256: String, expectedVersion: String) throws {
        let fm = FileManager.default
        let staging = working.deletingLastPathComponent()
            .appendingPathComponent("candidate-\(UUID().uuidString).sqlite")
        try fm.copyItem(at: downloadedURL, to: staging)
        defer { try? fm.removeItem(at: staging) }
        let bytes = try Data(contentsOf: staging)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard sha == trustedSHA256.lowercased() else {
            throw EmergencyDatabaseError.invalidRelease("SHA-256 mismatch")
        }
        let newMetadata = try Self.validate(staging)
        guard newMetadata["dataset_version"] == expectedVersion else {
            throw EmergencyDatabaseError.invalidRelease("Unexpected dataset version")
        }
        guard let newDate = newMetadata["published_at"], let oldDate = workingMetadata["published_at"],
              newDate > oldDate else {
            throw EmergencyDatabaseError.invalidRelease("Release is not newer")
        }
        if let connection = db {
            guard sqlite3_close(connection) == SQLITE_OK else { throw Self.sqlError(connection) }
            db = nil
        }
        var replaced = false
        do {
            // Durable backup before atomic same-filesystem rename. Previous stays
            // on disk after success; never truncate the working file in place.
            try Self.atomicCopy(working, to: previous)
            try Self.atomicRename(staging, to: working)
            replaced = true
            _ = try Self.validate(working)
            try Self.markRebuildable(working)
            db = try Self.open(working)
            workingMetadata = newMetadata
        } catch {
            // A failed pre-swap operation leaves working unchanged; a failed
            // post-swap check restores the saved file. Recovery on next launch
            // also uses previous if reopening is currently impossible.
            if replaced { try Self.atomicCopy(previous, to: working) }
            db = try Self.open(working)
            throw error
        }
    }

    // MARK: SQLite helpers

    private static func open(_ url: URL) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw EmergencyDatabaseError.sqlite("Cannot open SQLite file")
        }
        do {
            try execute(pointer, "PRAGMA foreign_keys=ON")
            try execute(pointer, "PRAGMA query_only=ON")
            try execute(pointer, "PRAGMA trusted_schema=OFF")
        } catch {
            sqlite3_close(pointer)
            throw error
        }
        return pointer
    }

    private static func sqlError(_ db: OpaquePointer) -> EmergencyDatabaseError {
        .sqlite(String(cString: sqlite3_errmsg(db)))
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw sqlError(db) }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func strings(_ db: OpaquePointer, _ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw sqlError(db) }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqlError(db) }
            var row: [String] = []
            for column in 0..<sqlite3_column_count(statement) {
                row.append(text(statement, column) ?? "")
            }
            result.append(row)
        }
    }

    // MARK: Validation

    private static func validate(_ file: URL) throws -> [String: String] {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            guard !fm.fileExists(atPath: file.path + suffix) else {
                throw EmergencyDatabaseError.invalidRelease("Release has SQLite sidecars")
            }
        }
        let db = try open(file)
        defer { sqlite3_close(db) }
        // Built once per validation and used for every timestamp (about 830 in the current
        // release). Local to this call, so no formatter is shared between threads.
        let utc = UTCTimestampChecker()
        guard try strings(db, "PRAGMA integrity_check") == [["ok"]],
              try strings(db, "PRAGMA foreign_key_check").isEmpty,
              try strings(db, "PRAGMA application_id") == [[applicationID]],
              try strings(db, "PRAGMA user_version") == [["1"]] else {
            throw EmergencyDatabaseError.invalidRelease("Integrity or schema version failure")
        }
        let tables = try strings(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").map { $0[0] }
        guard tables == ["areas", "contacts", "metadata", "services", "verifications"] else {
            throw EmergencyDatabaseError.invalidRelease("Unexpected tables")
        }
        let columns: [String: [String]] = [
            "areas": ["id", "parent_id", "name", "type", "country_code"],
            "services": ["id", "area_id", "name", "category", "description", "status"],
            "contacts": ["id", "service_id", "channel", "value", "notes", "availability", "status"],
            "verifications": ["id", "contact_id", "source_url", "checked_at", "result", "notes"],
            "metadata": ["key", "value"]
        ]
        for (table, expected) in columns {
            let actual = try strings(db, "PRAGMA table_info(\(table))").map { $0[1] }
            guard actual == expected else {
                throw EmergencyDatabaseError.invalidRelease("Column mismatch")
            }
        }
        var metadata: [String: String] = [:]
        for pair in try strings(db, "SELECT key,value FROM metadata") {
            guard metadata[pair[0]] == nil else {
                throw EmergencyDatabaseError.invalidRelease("Duplicate metadata")
            }
            metadata[pair[0]] = pair[1]
        }
        guard metadata["schema_version"] == "1",
              let version = metadata["dataset_version"], !version.isEmpty,
              let published = metadata["published_at"], utc.isValid(published),
              let hash = metadata["reviewed_input_sha256"], hash.count == 64 else {
            throw EmergencyDatabaseError.invalidRelease("Missing release metadata")
        }
        let checks = [
            "SELECT id FROM areas WHERE id<=0 OR trim(name)='' OR name IS NULL OR country_code NOT GLOB '[A-Z][A-Z]' OR length(country_code)<>2 OR country_code IS NULL OR type NOT IN ('country','territory','region','district','city') OR type IS NULL LIMIT 1",
            "SELECT a.id FROM areas a LEFT JOIN areas p ON a.parent_id=p.id WHERE (a.type IN ('country','territory') AND a.parent_id IS NOT NULL) OR (a.type NOT IN ('country','territory') AND a.parent_id IS NULL) OR (a.parent_id IS NOT NULL AND (p.id IS NULL OR a.country_code<>p.country_code OR CASE p.type WHEN 'country' THEN 0 WHEN 'territory' THEN 0 WHEN 'region' THEN 1 WHEN 'district' THEN 2 ELSE 3 END >= CASE a.type WHEN 'country' THEN 0 WHEN 'territory' THEN 0 WHEN 'region' THEN 1 WHEN 'district' THEN 2 ELSE 3 END)) LIMIT 1",
            "SELECT s.id FROM services s LEFT JOIN areas a ON s.area_id=a.id WHERE s.id<=0 OR a.id IS NULL OR trim(s.name)='' OR s.name IS NULL OR s.status NOT IN ('active','inactive') OR s.status IS NULL OR s.category NOT IN ('general_emergency','police','fire','medical','poison','rescue','crisis','other') OR s.category IS NULL LIMIT 1",
            "SELECT c.id FROM contacts c LEFT JOIN services s ON c.service_id=s.id WHERE c.id<=0 OR s.id IS NULL OR typeof(c.value)<>'text' OR trim(c.value)='' OR c.channel NOT IN ('voice','sms','web') OR c.channel IS NULL OR c.status NOT IN ('active','inactive') OR c.status IS NULL LIMIT 1",
            "SELECT c.id FROM contacts c WHERE NOT EXISTS (SELECT 1 FROM verifications v WHERE v.contact_id=c.id AND v.result='confirmed' AND length(trim(v.notes))>0) LIMIT 1",
            "SELECT v.id FROM verifications v LEFT JOIN contacts c ON v.contact_id=c.id WHERE v.id<=0 OR c.id IS NULL OR v.result NOT IN ('confirmed','inconclusive') OR v.result IS NULL OR (v.source_url NOT LIKE 'https://%' AND v.source_url NOT LIKE 'http://%') OR v.source_url IS NULL LIMIT 1",
            "SELECT s.id FROM services s WHERE NOT EXISTS (SELECT 1 FROM contacts c WHERE c.service_id=s.id) OR (s.status='active' AND NOT EXISTS (SELECT 1 FROM contacts c WHERE c.service_id=s.id AND c.status='active')) LIMIT 1",
            "SELECT service_id FROM contacts GROUP BY service_id,channel,replace(replace(replace(replace(value,' ',''),'-',''),'(',''),')','') HAVING count(*)>1 LIMIT 1",
            "SELECT area_id FROM services GROUP BY area_id,category,lower(name) HAVING count(*)>1 LIMIT 1",
            "SELECT country_code FROM areas WHERE parent_id IS NULL GROUP BY country_code HAVING count(*)>1 LIMIT 1"
        ]
        for query in checks {
            guard try strings(db, query).isEmpty else {
                throw EmergencyDatabaseError.invalidRelease("Invalid data relationships or evidence")
            }
        }
        for row in try strings(db, "SELECT checked_at FROM verifications") {
            guard utc.isValid(row[0]), row[0] <= published else {
                throw EmergencyDatabaseError.invalidRelease("Invalid verification timestamp")
            }
        }
        return metadata
    }

    /// Format and round-trip check only. Deliberately no comparison with the
    /// device clock, which may be wrong.
    ///
    /// Make one per validation run: the formatter and pattern are built once instead of once
    /// per timestamp. Not shared across threads or stored statically.
    private struct UTCTimestampChecker {
        private let formatter = ISO8601DateFormatter()
        // Constant, known-good pattern; same ICU syntax as String.range(of:options:.regularExpression).
        private let pattern = try! NSRegularExpression(
            pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")

        func isValid(_ value: String) -> Bool {
            let range = NSRange(value.startIndex..., in: value)
            guard pattern.firstMatch(in: value, range: range) != nil else { return false }
            guard let date = formatter.date(from: value) else { return false }
            return formatter.string(from: date) == value
        }
    }

    /// Reads only the release date, with no validation. Used to decide whether a file is
    /// worth validating, never to decide that a file is safe to install.
    private static func publishedAt(of file: URL) -> String? {
        guard let db = try? open(file) else { return nil }
        defer { sqlite3_close(db) }
        guard let rows = try? strings(db, "SELECT value FROM metadata WHERE key='published_at'"),
              rows.count == 1, let value = rows[0].first, !value.isEmpty else { return nil }
        return value
    }

    // MARK: File helpers

    /// Copies the first valid candidate over the working file and returns its metadata.
    @discardableResult
    private static func restoreWorking(from candidates: [URL], to target: URL) throws -> [String: String] {
        var lastError: Error = EmergencyDatabaseError.invalidRelease("No valid emergency database")
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            do {
                let metadata = try validate(candidate)
                try atomicCopy(candidate, to: target)
                return metadata
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func atomicCopy(_ source: URL, to target: URL) throws {
        let tmp = target.deletingLastPathComponent().appendingPathComponent("copy-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try markRebuildable(tmp)
        try atomicRename(tmp, to: target)
    }

    private static func atomicRename(_ source: URL, to target: URL) throws {
        let status = source.path.withCString { src in
            target.path.withCString { dst in Darwin.rename(src, dst) }
        }
        guard status == 0 else { throw EmergencyDatabaseError.replacement(errno) }
    }

    private static func markRebuildable(_ file: URL) throws {
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: file.path)
    }
}
