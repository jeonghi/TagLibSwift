import Foundation
import SwiftUI
import TagLibSwift

/// A single editable PropertyMap entry (key + newline-free list of values),
/// used to drive the PropertyMap editor UI.
struct PropertyEntry: Identifiable, Equatable {
    let id = UUID()
    var key: String
    /// Values joined by " | " for a single TextField; split back on save.
    var valuesText: String

    var values: [String] {
        valuesText
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Observable wrapper around a `TagLibSwift.AudioFile` that surfaces every SDK
/// feature to the SwiftUI layer and mediates load / edit / save.
@MainActor
final class DemoModel: ObservableObject {

    // Which file is currently open. `currentPath` is the on-disk path used
    // internally (reopen, etc.) and is NOT shown in the UI — showing the raw
    // absolute path leaks the sandbox/host location. `displayName` is the
    // user-facing label (just the file name).
    @Published var currentPath: String = ""
    @Published var displayName: String = ""
    @Published var isValid: Bool = false
    /// True when the active `AudioFile` was opened from an in-memory buffer
    /// (`init(data:fileExtension:)`) rather than from a path on disk.
    @Published var isMemoryBacked: Bool = false

    // Base tag fields (bound to file.tag.* on save).
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var comment = ""
    @Published var genre = ""
    @Published var year: Int = 0
    @Published var track: Int = 0
    @Published var tagIsEmpty = false

    // Audio properties (read-only).
    @Published var audioProps: AudioProperties?

    // PropertyMap editor rows.
    @Published var propertyEntries: [PropertyEntry] = []
    @Published var rejectedKeys: [String] = []

    // Cover art.
    @Published var pictures: [TagLibSwift.Picture] = []

    // Generic complex properties (format-specific, e.g. embedded pictures,
    // chapters, MusicBrainz IDs). Read-only display.
    @Published var complexPropertyKeys: [String] = []
    @Published var complexProperties: [String: [[String: ComplexValue]]] = [:]

    // User feedback.
    @Published var statusMessage: String = ""
    @Published var isError = false

    private var file: AudioFile?
    private var securityScopedURL: URL?

    // MARK: - Loading

    /// Copy the bundled read-only sample into a writable temp location and open
    /// it. A bundled resource cannot be saved back to, so we always work on a
    /// copy.
    func loadBundledSample() {
        guard let bundled = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            report("Bundled sample.mp3 not found in app bundle.", error: true)
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TagLibSwiftDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent("sample.mp3")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: bundled, to: dest)
        } catch {
            report("Failed to copy sample to temp: \(error.localizedDescription)", error: true)
            return
        }
        releaseSecurityScope()
        open(path: dest.path, display: "temp/sample.mp3")
    }

    /// Open a user-selected file from `.fileImporter`, handling iOS
    /// security-scoped resources.
    func loadImported(url: URL) {
        releaseSecurityScope()
        let didAccess = url.startAccessingSecurityScopedResource()
        if didAccess {
            securityScopedURL = url
        }
        open(path: url.path, display: url.lastPathComponent)
    }

    private func open(path: String, display: String) {
        guard let opened = AudioFile(path: path) else {
            report("AudioFile could not parse: \(display)", error: true)
            self.file = nil
            self.isValid = false
            return
        }
        self.file = opened
        self.currentPath = path
        self.displayName = display
        self.isValid = opened.isValid
        self.isMemoryBacked = false
        refreshFromFile()
        report("Opened \(display) (isValid: \(opened.isValid), isNull: \(opened.isNull))", error: false)
    }

    /// Pull every field from the underlying AudioFile into published state.
    private func refreshFromFile() {
        guard let file else { return }
        let tag = file.tag
        title = tag.title
        artist = tag.artist
        album = tag.album
        comment = tag.comment
        genre = tag.genre
        year = Int(tag.year)
        track = Int(tag.track)
        tagIsEmpty = tag.isEmpty

        audioProps = file.audioProperties

        propertyEntries = file.properties
            .sorted { $0.key < $1.key }
            .map { PropertyEntry(key: $0.key, valuesText: $0.value.joined(separator: " | ")) }

        pictures = file.pictures
        rejectedKeys = []

        complexPropertyKeys = file.complexPropertyKeys.sorted()
        var complexMap: [String: [[String: ComplexValue]]] = [:]
        for key in complexPropertyKeys {
            complexMap[key] = file.complexProperties(key)
        }
        complexProperties = complexMap
    }

    // MARK: - In-memory I/O

    /// The file extension (no leading dot) of the currently open file, derived
    /// from `currentPath`/`displayName`. Used to hint `AudioFile(data:fileExtension:)`.
    private var currentFileExtension: String {
        let name = displayName.isEmpty ? currentPath : displayName
        return (name as NSString).pathExtension
    }

    /// Read the current file's bytes from disk and reopen them as an
    /// in-memory-backed `AudioFile`, replacing the active file.
    func openInMemoryCopy() {
        guard !currentPath.isEmpty else {
            report("No file open.", error: true)
            return
        }
        let ext = currentFileExtension
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: currentPath)) else {
            report("Could not read current file's bytes from disk.", error: true)
            return
        }
        guard let memoryFile = AudioFile(data: bytes, fileExtension: ext) else {
            report("AudioFile(data:fileExtension:) failed to parse the in-memory copy.", error: true)
            return
        }
        self.file = memoryFile
        self.isValid = memoryFile.isValid
        self.isMemoryBacked = true
        refreshFromFile()
        report("Opened in-memory copy (\(bytes.count) bytes).", error: false)
    }

    /// Serialize the active memory-backed file, then reopen the resulting
    /// `Data` and confirm the title round-trips, proving `serialized()` +
    /// `init(data:fileExtension:)` compose correctly.
    func serializeAndVerify() {
        guard let file else {
            report("No file open.", error: true)
            return
        }
        do {
            let data = try file.serialized()
            let expectedTitle = file.tag.title
            guard let reopened = AudioFile(data: data, fileExtension: currentFileExtension) else {
                report("Serialized \(data.count) bytes, but reopening them failed.", error: true)
                return
            }
            if reopened.tag.title == expectedTitle {
                report("Serialized \(data.count) bytes; verified title round-trips (\"\(expectedTitle)\").", error: false)
            } else {
                report("Serialized \(data.count) bytes, but title mismatched on reopen (expected \"\(expectedTitle)\", got \"\(reopened.tag.title)\").", error: true)
            }
        } catch AudioFileError.notMemoryBacked {
            report("Serialize failed: file is path-backed, not memory-backed.", error: true)
        } catch {
            report("Serialize failed: \(error)", error: true)
        }
    }

    // MARK: - PropertyMap editing

    func addPropertyEntry() {
        propertyEntries.append(PropertyEntry(key: "NEWKEY", valuesText: "value"))
    }

    func deletePropertyEntries(at offsets: IndexSet) {
        propertyEntries.remove(atOffsets: offsets)
    }

    // MARK: - Cover art editing

    /// Set a single front-cover picture from raw image bytes.
    func setCoverArt(data: Data, mimeType: String) {
        let picture = TagLibSwift.Picture(
            data: data,
            mimeType: mimeType,
            description: "Set from TagLibSwiftDemo",
            pictureType: .frontCover
        )
        file?.setPictures([picture])
        pictures = file?.pictures ?? []
        report("Cover art staged (\(data.count) bytes). Press Save to persist.", error: false)
    }

    func clearCoverArt() {
        file?.setPictures([])
        pictures = file?.pictures ?? []
        report("Cover art cleared. Press Save to persist.", error: false)
    }

    // MARK: - Save

    /// Write all edited tag fields + PropertyMap + pictures back through the SDK
    /// and persist to disk.
    func save() {
        guard let file else {
            report("No file open.", error: true)
            return
        }

        // 1. Base tag fields.
        let tag = file.tag
        tag.title = title
        tag.artist = artist
        tag.album = album
        tag.comment = comment
        tag.genre = genre
        tag.year = UInt(max(0, year))
        tag.track = UInt(max(0, track))

        // 2. PropertyMap — note: setProperties overwrites all text tags, so the
        //    base-tag fields above are also representable here. We apply the
        //    editor rows and surface any rejected keys.
        var map: PropertyMap = [:]
        for entry in propertyEntries where !entry.key.isEmpty {
            map[entry.key, default: []].append(contentsOf: entry.values)
        }
        let rejected = file.setProperties(map)
        rejectedKeys = rejected.keys.sorted()

        // 3. Persist.
        do {
            try file.save()
            tagIsEmpty = file.tag.isEmpty
            if rejectedKeys.isEmpty {
                report("Saved successfully.", error: false)
            } else {
                report("Saved. Rejected keys: \(rejectedKeys.joined(separator: ", "))", error: false)
            }
        } catch {
            report("Save failed: \(error)", error: true)
        }
    }

    /// Reopen the current file from disk to prove persistence.
    func reopenToVerify() {
        let path = currentPath
        guard !path.isEmpty else { return }
        guard let reopened = AudioFile(path: path) else {
            report("Reopen failed.", error: true)
            return
        }
        self.file = reopened
        self.isMemoryBacked = false
        refreshFromFile()
        report("Reopened from disk — values reflect what was persisted.", error: false)
    }

    // MARK: - Helpers

    private func report(_ message: String, error: Bool) {
        statusMessage = message
        isError = error
    }

    private func releaseSecurityScope() {
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
    }
}
