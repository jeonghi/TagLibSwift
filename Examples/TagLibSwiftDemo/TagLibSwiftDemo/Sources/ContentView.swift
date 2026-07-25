import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

struct ContentView: View {
    @StateObject private var model = DemoModel()

    @State private var showAudioImporter = false
    @State private var showImageImporter = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                fileSection
                tagSection
                audioPropertiesSection
                propertyMapSection
                coverArtSection
                saveSection
                statusSection
            }
            .navigationTitle("TagLibSwift Demo")
            .onAppear {
                if model.currentPath.isEmpty {
                    model.loadBundledSample()
                }
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    model.loadImported(url: url)
                } else if case let .failure(error) = result {
                    model.statusMessage = "Import failed: \(error.localizedDescription)"
                    model.isError = true
                }
            }
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        Section("File") {
            LabeledContent("Path", value: model.currentPath.isEmpty ? "—" : model.currentPath)
                .lineLimit(2)
            LabeledContent("isValid", value: model.isValid ? "true" : "false")
            LabeledContent("tag.isEmpty", value: model.tagIsEmpty ? "true" : "false")
            Button("Load bundled sample") { model.loadBundledSample() }
            Button("Open other audio file…") { showAudioImporter = true }
        }
    }

    private var tagSection: some View {
        Section("Tag") {
            LabeledField(label: "Title", text: $model.title)
            LabeledField(label: "Artist", text: $model.artist)
            LabeledField(label: "Album", text: $model.album)
            LabeledField(label: "Comment", text: $model.comment)
            LabeledField(label: "Genre", text: $model.genre)
            Stepper("Year: \(model.year)", value: $model.year, in: 0...9999)
            Stepper("Track: \(model.track)", value: $model.track, in: 0...999)
        }
    }

    @ViewBuilder
    private var audioPropertiesSection: some View {
        Section("Audio Properties (read-only)") {
            if let p = model.audioProps {
                LabeledContent("Length", value: formatDuration(p.lengthInSeconds))
                LabeledContent("Length (ms)", value: "\(p.lengthInMilliseconds)")
                LabeledContent("Bitrate", value: "\(p.bitrate) kbps")
                LabeledContent("Sample rate", value: "\(p.sampleRate) Hz")
                LabeledContent("Channels", value: "\(p.channels)")
            } else {
                Text("No audio properties available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var propertyMapSection: some View {
        Section("PropertyMap (all text tags)") {
            ForEach($model.propertyEntries) { $entry in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("KEY", text: $entry.key)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        #endif
                    TextField("values (separate with |)", text: $entry.valuesText)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: model.deletePropertyEntries)

            Button("Add entry") { model.addPropertyEntry() }

            if !model.rejectedKeys.isEmpty {
                Text("Rejected on save: \(model.rejectedKeys.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var coverArtSection: some View {
        Section("Cover Art") {
            if let first = model.pictures.first {
                if let image = ImageCodec.image(from: first.data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                }
                LabeledContent("MIME", value: first.mimeType)
                LabeledContent("Bytes", value: "\(first.data.count)")
                LabeledContent("Type", value: first.pictureType.rawValue)
                LabeledContent("Description", value: first.description.isEmpty ? "—" : first.description)
                Button("Remove cover art", role: .destructive) { model.clearCoverArt() }
            } else {
                Text("No embedded pictures.")
                    .foregroundStyle(.secondary)
            }

            #if os(iOS)
            PhotosPicker("Pick image…", selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let (png, mime) = ImageCodec.pngData(from: data) {
                            model.setCoverArt(data: png, mimeType: mime)
                        } else {
                            model.statusMessage = "Could not load picked image."
                            model.isError = true
                        }
                    }
                }
            #else
            Button("Pick image…") { showImageImporter = true }
                .fileImporter(
                    isPresented: $showImageImporter,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in
                    guard case let .success(urls) = result, let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let raw = try? Data(contentsOf: url),
                       let (png, mime) = ImageCodec.pngData(from: raw) {
                        model.setCoverArt(data: png, mimeType: mime)
                    } else {
                        model.statusMessage = "Could not load picked image."
                        model.isError = true
                    }
                }
            #endif
        }
    }

    private var saveSection: some View {
        Section("Save") {
            Button("Save to disk") { model.save() }
                .buttonStyle(.borderedProminent)
            Button("Reopen from disk (verify persistence)") { model.reopenToVerify() }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !model.statusMessage.isEmpty {
            Section("Status") {
                Text(model.statusMessage)
                    .foregroundStyle(model.isError ? .red : .green)
                    .font(.callout)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A label + TextField row that stays legible on both iOS and macOS.
private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
        }
    }
}
