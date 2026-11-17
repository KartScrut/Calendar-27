import SwiftUI
import TwelveCore

/// Preferences, account, privacy controls and accessibility.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var editingInterests = false
    @State private var confirmErase = false
    @State private var confirmDeleteAccount = false
    @State private var working = false
    @State private var notice: String?
    @State private var exportURL: URL?
    @State private var notificationsDenied = false
    #if DEBUG
    @State private var simulatedDate = Date()
    #endif

    var body: some View {
        let _ = app.revision
        NavigationStack {
            Form {
                Section {
                    TextField("Your name (optional)", text: $name)
                        .textContentType(.givenName)
                        .onSubmit(saveName)
                        .onChange(of: name) { _, new in if new.count > 60 { name = String(new.prefix(60)) } }
                } header: {
                    Text("You")
                } footer: {
                    Text("Used only to greet you and, if you choose, on your Year in Review card.")
                }

                Section("Interests") {
                    Button {
                        editingInterests = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.profile.interests.compactMap { Interests.category($0.category)?.name }.joined(separator: ", "))
                                    .foregroundStyle(Color.ink)
                                Text("Shapes your daily Spark").font(.caption).foregroundStyle(Color.inkSoft)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.inkSoft)
                        }
                    }
                    Picker("My year should feel", selection: Binding(get: { app.profile.feeling ?? .surprise },
                                                                      set: { f in app.updateProfile { $0.feeling = f } })) {
                        ForEach(YearFeeling.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ReminderRows(denied: $notificationsDenied)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications are off for TWELVE in the Settings app. Turn them on there to receive reminders."
                         : "Gentle, optional, and always based on your real progress.")
                }

                accountSection

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Save or share the export", systemImage: "square.and.arrow.up") }
                    } else {
                        Button {
                            exportURL = app.exportFile()
                            if exportURL == nil { notice = "The export couldn't be created. Please try again." }
                        } label: {
                            Label("Export my data", systemImage: "doc.text")
                        }
                    }
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Erase This iPhone", systemImage: "trash")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Your writing is private. Photos are stored only on this iPhone and are never uploaded. TWELVE has no ads and no tracking. The export is a readable file of everything stored here.")
                }

                Section {
                    Toggle("Offer gentler activity options", isOn: Binding(get: { app.profile.useAccessibleVariant },
                                                                           set: { on in app.updateProfile { $0.useAccessibleVariant = on } }))
                    LabeledContent("Calendar time zone", value: app.profile.timeZoneID.replacingOccurrences(of: "_", with: " "))
                    if app.profile.timeZoneID != TimeZone.current.identifier {
                        Button("Use this iPhone's time zone") {
                            app.updateProfile { $0.timeZoneID = TimeZone.current.identifier }
                        }
                    }
                } header: {
                    Text("Accessibility & calendar")
                } footer: {
                    Text("Physical challenges always have an alternative that counts equally. TWELVE follows your system settings for text size, Reduce Motion and contrast. Your calendar time zone stays fixed when you travel, so days you've already logged never move; change it here if you relocate.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    NavigationLink("Privacy") { PrivacyText() }
                }

                #if DEBUG
                developerSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .paperScreen()
            .navigationTitle("Profile")
            .onAppear {
                name = app.profile.displayName
                Task { notificationsDenied = await app.notifications.isDenied() }
            }
            .onDisappear(perform: saveName)
            .sheet(isPresented: $editingInterests) { InterestEditor() }
            .alert("TWELVE", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
            .confirmationDialog("Erase everything on this iPhone?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase This iPhone", role: .destructive) {
                    Task {
                        if app.auth.isSignedIn { await app.signOut() }
                        app.eraseDevice()
                    }
                }
            } message: {
                Text(app.auth.isSignedIn
                     ? "This removes all progress, writing and photos from this iPhone and signs you out. Progress already backed up stays in your account; photos are not backed up and will be lost."
                     : "This permanently removes all progress, writing and photos. As a guest, there is no backup.")
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Delete Account and All Data", role: .destructive) {
                    working = true
                    Task {
                        do {
                            try await app.deleteAccount()
                        } catch {
                            notice = (error as? LocalizedError)?.errorDescription ?? "The account couldn't be deleted. Please try again."
                        }
                        working = false
                    }
                }
            } message: {
                Text("This permanently deletes your account and everything stored with it on our servers, and erases this iPhone. It can't be undone.")
            }
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != app.profile.displayName { app.updateProfile { $0.displayName = trimmed } }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if !app.auth.isAvailable {
                Label("Guest · saved on this iPhone", systemImage: "iphone")
                Text("Cloud backup isn't set up in this build yet.").font(.footnote).foregroundStyle(Color.inkSoft)
            } else if app.auth.isSignedIn {
                LabeledContent("Signed in", value: app.auth.email ?? "Apple ID")
                LabeledContent("Backup", value: syncText)
                Button("Back up now") { Task { await app.sync.syncNow() } }
                    .disabled(app.sync.status == .syncing)
                Button("Sign Out") {
                    working = true
                    Task { await app.signOut(); working = false }
                }
                Button("Delete Account", role: .destructive) { confirmDeleteAccount = true }
            } else {
                Label("Guest · saved on this iPhone", systemImage: "iphone")
                Button("Sign in to back up") { app.sheet = .account }
                if app.auth.sessionExpiredNotice {
                    Text("Your sign-in expired. Your progress is safe on this iPhone — sign in again to resume backup.")
                        .font(.footnote).foregroundStyle(Color.accentText)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(app.auth.isSignedIn
                 ? "Signing out keeps your progress on this iPhone."
                 : "As a guest, your progress lives only on this iPhone. If the app is deleted, it can't be recovered.")
        }
        .disabled(working)
    }

    private var syncText: String {
        switch app.sync.status {
        case .syncing: return "Backing up…"
        case .offline: return "Offline · will retry"
        case .failed: return "Will retry"
        case .idle:
            if app.sync.rejectedCount > 0 { return "Up to date · \(app.sync.rejectedCount) kept on device only" }
            if let at = app.sync.lastSyncedAt { return "Up to date · \(at.formatted(date: .omitted, time: .shortened))" }
            return "Ready"
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section {
            DatePicker("Simulated date", selection: $simulatedDate, displayedComponents: [.date])
            Button(app.isDemo ? "Jump to this date" : "Preview this date") { app.simulate(date: simulatedDate) }
            if app.isDemo {
                Button("Stamp earlier months (demo)") { app.demoCompleteEarlierMonths() }
                Button("Reset demo data") { app.demoReset() }
                Button("Return to today") { app.simulate(date: nil) }
            }
        } header: {
            Text("Preview mode (debug builds only)")
        } footer: {
            Text("Jump to any date to try the app as it will be during 2027. Preview mode uses a separate demo database and never syncs, so it can't affect real progress. This section is not included in App Store builds.")
        }
        .onAppear {
            if !app.isDemo {
                simulatedDate = YearCalendar(year: AppModel.year, timeZone: .current).date(month: 2, day: 10, hour: 10)
            }
        }
    }
    #endif
}

/// Reminder toggles that ask the system for permission only when first needed.
private struct ReminderRows: View {
    @Environment(AppModel.self) private var app
    @Binding var denied: Bool

    var body: some View {
        let reminders = app.profile.reminders
        Toggle("A daily discovery", isOn: binding(\.dailySpark))
        if reminders.dailySpark {
            DatePicker("Time", selection: Binding(get: {
                Calendar.current.date(bySettingHour: reminders.dailyMinutes / 60, minute: reminders.dailyMinutes % 60, second: 0, of: Date()) ?? Date()
            }, set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                app.updateProfile { p in
                    var r = p.reminders
                    r.dailyMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                    p.reminders = r
                }
            }), displayedComponents: .hourAndMinute)
        }
        Toggle("Monthly challenge announcements", isOn: binding(\.monthlyReveal))
        Toggle("Occasional progress reminders", isOn: binding(\.progress))
    }

    private func binding(_ keyPath: WritableKeyPath<ReminderPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { app.profile.reminders[keyPath: keyPath] }, set: { on in
            if on {
                Task {
                    let granted = await app.notifications.requestAuthorization()
                    denied = !granted
                    guard granted else { return }
                    set(keyPath, true)
                }
            } else {
                set(keyPath, false)
            }
        })
    }

    private func set(_ keyPath: WritableKeyPath<ReminderPreferences, Bool>, _ value: Bool) {
        app.updateProfile { p in
            var r = p.reminders
            r[keyPath: keyPath] = value
            p.reminders = r
        }
    }
}

private struct InterestEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var interests: [InterestChoice] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose two to four.").font(.subheadline).foregroundStyle(Color.inkSoft)
                    InterestGrid(interests: $interests)
                    SubcategoryPicker(interests: $interests)
                }
                .padding(20)
            }
            .paperScreen()
            .navigationTitle("Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.updateProfile { $0.interests = interests }
                        dismiss()
                    }
                    .disabled(interests.count < Interests.minimumSelection)
                }
            }
            .onAppear { interests = app.profile.interests }
        }
    }
}

private struct PrivacyText: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy, plainly").font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                ForEach([
                    ("What we keep", "Your interests and preferences, the activity you log toward each month, and your achievements. If you sign in, these are stored in your account so they can be backed up and kept in step across devices."),
                    ("What stays on your iPhone", "Photos you add never leave this device. As a guest, nothing leaves this device at all."),
                    ("What we never do", "We don't sell your data, show ads, use your writing for advertising, or include third-party tracking. We never record your location."),
                    ("Health", "Health access is optional and read-only. If you connect it, TWELVE reads walking workouts for the walking month and nothing else."),
                    ("Your controls", "You can export everything, erase this iPhone, or delete your account and all server-side data at any time from Profile."),
                ], id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(.headline).foregroundStyle(Color.ink)
                        Text(item.1).font(.body).foregroundStyle(Color.inkSoft)
                    }
                }
            }
            .padding(22)
        }
        .paperScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
