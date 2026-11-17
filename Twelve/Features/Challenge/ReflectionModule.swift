import PhotosUI
import SwiftUI
import TwelveCore

/// Guided private writing. Used for January's observations, July's acts of
/// kindness, August's dishes and December's moments.
struct ReflectionModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    @State private var text = ""
    @State private var title = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var editing: ActivityEntry?
    @State private var deleting: ActivityEntry?
    @FocusState private var focused: Bool

    private var needsTitle: Bool { challenge.entryKind == "dish" }
    private var allowsPhoto: Bool { challenge.entryKind == "dish" || challenge.entryKind == "moment" }
    private var draftKey: String { "draft.\(challenge.id)" }

    private var prompt: String {
        guard !challenge.prompts.isEmpty else { return "What would you like to remember?" }
        let day = app.calendar.components(for: app.now).day
        return challenge.prompts[(day + app.entries(for: challenge).count) % challenge.prompts.count]
    }

    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return needsTitle ? hasTitle : hasText
    }

    var body: some View {
        let _ = app.revision
        let entries = app.entries(for: challenge).reversed()
        let progress = app.progress(for: challenge)
        let open = app.isOpen(challenge)
        let countedToday = challenge.metric == .distinctDays && entries.contains { $0.dayKey == app.todayKey }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ModuleProgressHeader(challenge: challenge, progress: progress)

                if open {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(prompt).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                            if needsTitle {
                                TextField("Name of the dish", text: $title)
                                    .font(.body.weight(.medium))
                                    .padding(12)
                                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            TextField(needsTitle ? "A note, if you like" : "Write a sentence or two…", text: $text, axis: .vertical)
                                .lineLimit(4...10)
                                .focused($focused)
                                .padding(12)
                                .background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: text) { _, new in
                                    // Auto-save the draft so nothing typed is lost.
                                    UserDefaults.standard.set(new, forKey: draftKey)
                                }
                            if allowsPhoto {
                                HStack(spacing: 10) {
                                    if let chosenPhoto = photo {
                                        Image(uiImage: chosenPhoto).resizable().scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .accessibilityLabel("Chosen photo")
                                        Button("Remove photo") { photo = nil; photoItem = nil }
                                            .font(.footnote).foregroundStyle(Color.accentText)
                                    } else {
                                        PhotosPicker(selection: $photoItem, matching: .images) {
                                            Label("Add a photo", systemImage: "photo").font(.footnote.weight(.semibold))
                                        }
                                        if CameraPicker.isAvailable {
                                            Button { showCamera = true } label: {
                                                Label("Camera", systemImage: "camera").font(.footnote.weight(.semibold))
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(Color.accentText)
                                Text("Photos stay on this iPhone.").font(.caption2).foregroundStyle(Color.inkSoft)
                            }
                            if countedToday {
                                Text("Today is already counted. You're welcome to write more — one observation counts per day.")
                                    .font(.footnote).foregroundStyle(Color.sageText)
                            }
                            PrimaryButton(title: "Save", systemImage: "checkmark", action: save)
                                .disabled(!canSave)
                        }
                    }
                } else {
                    InfoBanner(symbol: "archivebox", text: "This month has closed. Your entries are kept here to look back on.")
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(entries.isEmpty ? "Your entries" : "Your entries · \(entries.count)")
                    if entries.isEmpty {
                        EmptyNote(symbol: "square.and.pencil", title: "Nothing here yet",
                                  message: open ? "Your first entry will appear here. It stays private." : "Nothing was written this month.")
                    }
                    ForEach(Array(entries), id: \.id) { entry in
                        EntryRow(entry: entry, editable: true, onEdit: { editing = entry }, onDelete: { deleting = entry })
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { text = UserDefaults.standard.string(forKey: draftKey) ?? "" }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { photo = $0 }.ignoresSafeArea()
        }
        .sheet(item: $editing) { entry in
            EditEntrySheet(entry: entry)
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting { app.remove(d) }
                deleting = nil
            }
        } message: {
            Text("This can't be undone. If it had a photo, the photo is removed too.")
        }
    }

    private func save() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = photo.flatMap(PhotoStore.save)
        let saved = app.log(challenge, title: name.isEmpty ? nil : String(name.prefix(200)),
                            text: body.isEmpty ? nil : String(body.prefix(4000)), photoFile: file)
        if saved != nil {
            Haptics.success()
            text = ""; title = ""; photo = nil; photoItem = nil
            UserDefaults.standard.removeObject(forKey: draftKey)
            focused = false
        } else if let file {
            PhotoStore.delete(file)
        }
    }
}

/// Progress summary shown at the top of every activity module.
struct ModuleProgressHeader: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition
    let progress: ChallengeProgress

    var body: some View {
        let done = app.summary.state(month: challenge.month) == .completed
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(fraction: done ? 1 : progress.fraction, lineWidth: 6, tint: .terracotta, track: .hairline)
                Image(systemName: done ? "checkmark" : challenge.symbol)
                    .font(.body.weight(done ? .bold : .regular))
                    .foregroundStyle(Color.accentText)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                RollingNumber(text: ProgressCalculator.label(for: challenge, progress: progress),
                              font: .editorial(.title3, weight: .medium))
                Text(done ? challenge.completionLine : challenge.tagline)
                    .font(.footnote).foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One saved entry in a personal archive.
struct EntryRow: View {
    let entry: ActivityEntry
    var editable = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        PaperCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                if entry.photoFile != nil {
                    LocalPhoto(file: entry.photoFile)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Photo")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentText)
                    if let title = entry.title, !title.isEmpty {
                        Text(title).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                    }
                    if let text = entry.text, !text.isEmpty {
                        Text(text).font(.body).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if editable {
                    Menu {
                        Button("Edit", systemImage: "pencil", action: onEdit)
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Color.inkSoft).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Entry options")
                }
            }
        }
    }
}

struct EditEntrySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: ActivityEntry
    @State private var text = ""
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                if entry.title != nil || entry.kind == "dish" {
                    TextField("Title", text: $title)
                }
                TextField("Entry", text: $text, axis: .vertical).lineLimit(5...14)
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        app.update(entry, text: t.isEmpty ? nil : String(t.prefix(4000)), title: name.isEmpty ? nil : String(name.prefix(200)))
                        dismiss()
                    }
                }
            }
            .onAppear { text = entry.text ?? ""; title = entry.title ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}
