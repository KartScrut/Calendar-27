import PhotosUI
import SwiftUI
import TwelveCore

/// April's collection of everyday details. Photos never leave the device.
struct PhotoModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var viewing: ActivityEntry?
    @State private var working = false

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        let _ = app.revision
        let entries = app.entries(for: challenge).reversed()
        let open = app.isOpen(challenge)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleProgressHeader(challenge: challenge, progress: app.progress(for: challenge))

                if open {
                    HStack(spacing: 12) {
                        if CameraPicker.isAvailable {
                            PrimaryButton(title: "Camera", systemImage: "camera") { showCamera = true }
                        }
                        PhotosPicker(selection: $picked, maxSelectionCount: 5, matching: .images) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                Text(working ? "Adding…" : "Choose photos")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(working)
                    }
                    Label("Photos are stored only on this iPhone. They are never uploaded.", systemImage: "lock")
                        .font(.caption).foregroundStyle(Color.inkSoft)
                } else {
                    InfoBanner(symbol: "archivebox", text: "This month has closed. Your photos are kept here.")
                }

                if entries.isEmpty {
                    EmptyNote(symbol: "camera.macro", title: "An empty wall",
                              message: open ? "Look for a texture, a shadow, a colour, something worn by use." : "No photos were added this month.")
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(entries), id: \.id) { entry in
                            Button {
                                viewing = entry
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(LocalPhoto(file: entry.photoFile))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(LiftButtonStyle())
                            .accessibilityLabel(entry.text.map { "Photo: \($0)" } ?? "Photo from \(entry.date.formatted(.dateTime.day().month(.wide)))")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            working = true
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        add(image)
                    }
                }
                picked = []
                working = false
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { add($0) }.ignoresSafeArea()
        }
        .sheet(item: $viewing) { entry in
            PhotoDetail(entry: entry)
        }
    }

    private func add(_ image: UIImage) {
        guard let file = PhotoStore.save(image) else { return }
        if app.log(challenge, photoFile: file) != nil {
            Haptics.success()
        } else {
            PhotoStore.delete(file)
        }
    }
}

private struct PhotoDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: ActivityEntry
    @State private var caption = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = PhotoStore.image(entry.photoFile) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Photo")
                    }
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentText)
                    TextField("Add a caption", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete photo", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(20)
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let c = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        if c != (entry.text ?? "") { app.update(entry, text: c.isEmpty ? nil : String(c.prefix(500))) }
                        dismiss()
                    }
                }
            }
            .onAppear { caption = entry.text ?? "" }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    app.remove(entry)
                    dismiss()
                }
            } message: {
                Text("It will be removed from TWELVE. Your Photos library isn't affected.")
            }
        }
    }
}
