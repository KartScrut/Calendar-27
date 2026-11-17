import SwiftUI
import TwelveCore

/// May's reading log: say what you're reading, then log pages as you go.
struct ReadingModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    @State private var bookID: UUID?
    @State private var pagesText = ""
    @State private var newTitle = ""
    @State private var newAuthor = ""
    @State private var addingBook = false
    @State private var problem: String?
    @State private var deleting: ActivityEntry?
    @FocusState private var pagesFocused: Bool

    private static let milestones = [15, 30, 45, 60]

    var body: some View {
        let _ = app.revision
        let books = app.store.books()
        let entries = app.entries(for: challenge).reversed()
        let progress = app.progress(for: challenge)
        let open = app.isOpen(challenge)
        let pages = Int(progress.value)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ModuleProgressHeader(challenge: challenge, progress: progress)

                // Small milestones along the way.
                HStack(spacing: 0) {
                    ForEach(Self.milestones, id: \.self) { mark in
                        let reached = pages >= mark
                        VStack(spacing: 6) {
                            Image(systemName: reached ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(reached ? Color.goldText : Color.hairline)
                            Text("\(mark)").font(.caption.weight(.semibold)).foregroundStyle(reached ? Color.ink : Color.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(mark) pages, \(reached ? "reached" : "not yet reached")")
                    }
                }
                .padding(.vertical, 12)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline))

                if open {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Log your reading")
                            if books.isEmpty || addingBook {
                                TextField("Book title", text: $newTitle)
                                    .padding(12).background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                TextField("Author", text: $newAuthor)
                                    .padding(12).background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                HStack {
                                    SecondaryButton(title: "Add book", systemImage: "plus") { addBook() }
                                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                                    if !books.isEmpty {
                                        Button("Cancel") { addingBook = false }.font(.footnote).foregroundStyle(Color.inkSoft)
                                    }
                                }
                            } else {
                                Picker("Book", selection: Binding(get: { bookID ?? books.last?.id }, set: { bookID = $0 })) {
                                    ForEach(books, id: \.id) { book in
                                        Text(book.author.isEmpty ? book.title : "\(book.title) — \(book.author)").tag(Optional(book.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.accentText)
                                Button { addingBook = true } label: {
                                    Label("Another book", systemImage: "plus").font(.footnote.weight(.semibold))
                                }
                                .foregroundStyle(Color.accentText)

                                HStack(spacing: 12) {
                                    TextField("Pages read", text: $pagesText)
                                        .keyboardType(.numberPad)
                                        .focused($pagesFocused)
                                        .font(.title3.monospacedDigit())
                                        .padding(12)
                                        .background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .onChange(of: pagesText) { _, new in
                                            pagesText = String(new.filter(\.isNumber).prefix(3))
                                            problem = nil
                                        }
                                        .accessibilityLabel("Pages read")
                                    ForEach([5, 10, 20], id: \.self) { quick in
                                        Button("+\(quick)") { pagesText = "\(quick)"; Haptics.select() }
                                            .buttonStyle(.glass)
                                            .accessibilityLabel("\(quick) pages")
                                    }
                                }
                                if let problem {
                                    Text(problem).font(.footnote).foregroundStyle(Color.accentText)
                                }
                                PrimaryButton(title: "Log pages", systemImage: "checkmark", action: logPages)
                                    .disabled(Int(pagesText) == nil)
                            }
                        }
                    }
                } else {
                    InfoBanner(symbol: "archivebox", text: "This month has closed. Your reading log is kept here.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Reading log")
                    if entries.isEmpty {
                        EmptyNote(symbol: "book", title: "Nothing logged yet",
                                  message: open ? "Two pages a day gets you there." : "Nothing was logged this month.")
                    }
                    ForEach(Array(entries), id: \.id) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title ?? "Reading").font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                    .font(.caption).foregroundStyle(Color.inkSoft)
                            }
                            Spacer()
                            Text("\(Int(entry.amount)) pp").font(.numeral(20, weight: .medium)).foregroundStyle(Color.ink)
                            Button { deleting = entry } label: {
                                Image(systemName: "trash").font(.footnote).foregroundStyle(Color.inkSoft).frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Delete log entry")
                        }
                        .padding(.leading, 16).padding(.vertical, 8)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Delete this log entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting { app.remove(d) }
                deleting = nil
            }
        }
    }

    private func addBook() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let book = app.store.addBook(title: String(title.prefix(160)), author: String(newAuthor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)))
        bookID = book.id
        newTitle = ""; newAuthor = ""
        addingBook = false
        Haptics.tap()
    }

    private func logPages() {
        guard let pages = Int(pagesText) else { return }
        // Reject obviously invalid values instead of quietly accepting them.
        guard pages >= 1 else { problem = "Enter at least one page."; return }
        guard pages <= 500 else { problem = "That's a lot for one sitting. Log up to 500 pages at a time."; return }
        let books = app.store.books()
        let book = books.first { $0.id == bookID } ?? books.last
        if app.log(challenge, amount: Double(pages), ref: book?.id.uuidString, title: book?.title) != nil {
            Haptics.success()
            pagesText = ""
            pagesFocused = false
        }
    }
}
