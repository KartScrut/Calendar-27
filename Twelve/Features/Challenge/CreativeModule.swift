import PhotosUI
import SwiftUI
import TwelveCore

/// October: one small creative project, taken through three stages.
struct CreativeModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    private struct Stage {
        let ref: String
        let title: String
        let prompt: String
        let placeholder: String
    }

    private let stages = [
        Stage(ref: "1", title: "Choose an idea", prompt: "What will you make? Small is good.", placeholder: "A poem, a sketch, a shelf, a short film…"),
        Stage(ref: "2", title: "Make a first version", prompt: "Rough is fine. What did you make, and how did it go?", placeholder: "Describe your first version…"),
        Stage(ref: "3", title: "Improve or finish it", prompt: "What did you change? Finished beats perfect.", placeholder: "What's different now?"),
    ]

    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

    var body: some View {
        let _ = app.revision
        let entries = app.entries(for: challenge)
        let open = app.isOpen(challenge)
        let doneRefs = Set(entries.compactMap(\.ref))
        let nextStage = stages.first { !doneRefs.contains($0.ref) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ModuleProgressHeader(challenge: challenge, progress: app.progress(for: challenge))

                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    let entry = entries.first { $0.ref == stage.ref }
                    let isNext = nextStage?.ref == stage.ref
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)").font(.numeral(30, weight: .medium))
                                    .foregroundStyle(entry != nil ? Color.goldText : (isNext ? Color.accentText : Color.inkSoft))
                                Text(stage.title).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                                Spacer()
                                if entry != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sageText).accessibilityLabel("Done") }
                                else if !isNext { Image(systemName: "lock").foregroundStyle(Color.inkSoft).accessibilityLabel("Not yet available") }
                            }
                            if let entry {
                                if let body = entry.text { Text(body).font(.body).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true) }
                                if entry.photoFile != nil {
                                    LocalPhoto(file: entry.photoFile)
                                        .frame(maxWidth: .infinity).frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .accessibilityLabel("Photo of this stage")
                                }
                                Text(entry.date.formatted(.dateTime.day().month(.wide))).font(.caption).foregroundStyle(Color.inkSoft)
                            } else if isNext && open {
                                Text(stage.prompt).font(.subheadline).foregroundStyle(Color.inkSoft)
                                TextField(stage.placeholder, text: $text, axis: .vertical)
                                    .lineLimit(3...8)
                                    .padding(12)
                                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                HStack(spacing: 10) {
                                    if let photo {
                                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 52, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Button("Remove photo") { photo = nil; photoItem = nil }.font(.footnote)
                                    } else {
                                        PhotosPicker(selection: $photoItem, matching: .images) {
                                            Label("Add a photo (optional)", systemImage: "photo").font(.footnote.weight(.semibold))
                                        }
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(Color.accentText)
                                PrimaryButton(title: "Save stage \(index + 1)", systemImage: "checkmark") { save(stage) }
                                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } else {
                                Text(isNext ? "This month has closed." : "Finish the stage before this one first.")
                                    .font(.footnote).foregroundStyle(Color.inkSoft)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image }
            }
        }
    }

    private func save(_ stage: Stage) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let file = photo.flatMap(PhotoStore.save)
        if app.log(challenge, ref: stage.ref, title: stage.title, text: String(body.prefix(4000)), photoFile: file) != nil {
            Haptics.success()
            text = ""; photo = nil; photoItem = nil
        } else if let file {
            PhotoStore.delete(file)
        }
    }
}
