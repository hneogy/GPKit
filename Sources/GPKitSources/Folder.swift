import Foundation
import GPKit

/// Element sets from files a program already holds, a folder of answers kept from earlier fetches or captures made
/// elsewhere: no request, and no rule to keep, since nothing is asked of anyone.
///
/// A file's format is its extension's: `.csv`, `.json`, `.xml`, `.kvn`, and `.tle` or `.txt` for TLE. A file with
/// any other extension is left unread and named in `skipped`, as is a hidden file. A file GPKit refuses whole is
/// named in `failed` with GPKit's reason; one it reads, refusals and all, is in `files`. Files are read in name order.
public struct FolderSource: Sendable {

    public let folder: URL
    public let checksum: TLE.Checksum

    public init(folder: URL, checksum: TLE.Checksum = .verify) {
        self.folder = folder
        self.checksum = checksum
    }

    /// The format a file name says, or nil for one this source does not read.
    public static func format(of name: String) -> Format? {
        guard !name.hasPrefix("."), let dot = name.lastIndex(of: ".") else { return nil }
        switch name[name.index(after: dot)...].lowercased() {
        case "csv": return .csv
        case "json": return .json
        case "xml": return .xml
        case "kvn": return .kvn
        case "tle", "txt": return .tle
        default: return nil
        }
    }

    /// What reading the folder gave.
    public struct Reading: Sendable {
        /// Each file read, by name, in name order.
        public var files: [(name: String, file: ElementSetFile)] = []
        /// Files GPKit refused whole, by name, with its reason.
        public var failed: [(name: String, refusal: Refusal)] = []
        /// Files not read: hidden, or with an extension this source does not read.
        public var skipped: [String] = []
    }

    /// Reads every file of the folder once. Throws only where the folder cannot be listed.
    public func read() throws -> Reading {
        var reading = Reading()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        for name in names {
            let url = folder.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue { continue }
            guard let format = Self.format(of: name) else { reading.skipped.append(name); continue }
            let data: Data
            do { data = try Data(contentsOf: url) } catch {
                reading.failed.append((name, Refusal(.malformedFile, "the file could not be read: \(error)")))
                continue
            }
            do {
                reading.files.append((name, try ElementSets.read(data, as: format, checksum: checksum)))
            } catch {
                reading.failed.append((name, error))
            }
        }
        return reading
    }

    /// Reads the folder and merges every set it holds into the store, file by file in name order; the reports are
    /// summed, and the reading is given back beside them.
    public func load(into store: ElementSetStore) async throws -> (report: ElementSetStore.Report, reading: Reading) {
        let reading = try read()
        var total = ElementSetStore.Report()
        for (_, file) in reading.files {
            let report = await store.merge(file)
            total.added += report.added
            total.replaced += report.replaced
            total.unchanged += report.unchanged
            total.older += report.older
            total.conflicting += report.conflicting
            total.uncatalogued += report.uncatalogued
            total.refused += report.refused
        }
        return (total, reading)
    }
}
