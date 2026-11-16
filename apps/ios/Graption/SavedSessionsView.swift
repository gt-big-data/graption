import SwiftUI
import GraptionCore
import UniformTypeIdentifiers

@MainActor
struct SavedSessionsView: View {
    var activeSessionID: UUID? = nil
    @AppStorage("meetingRetentionDays") private var retentionDays = 0
    @State private var renaming: SavedSession?
    @State private var deleting: SavedSession?
    @State private var meetingTitle = ""
    @State private var store: FileSessionStore?
    @State private var recorder: SessionRecorder?
    @State private var sessions: [SavedSession] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                Section("Session persistence demo") {
                    if let recorder {
                        ForEach(recorder.session.captions) { caption in
                            CaptionRow(caption: caption)
                        }
                        Button(isSaving ? "Saving…" : "End Session & Save") {
                            Task { await endSession() }
                        }
                        .disabled(isSaving)
                    } else {
                        Button("Start Fake Session") { startFakeSession() }
                            .disabled(store == nil)
                    }
                    Text("Synthetic captions only. No microphone or audio recording.")
                        .font(.footnote)
                }
                #endif
                Section("Saved sessions") {
                    if sessions.isEmpty {
                        Text("No saved sessions yet.")
                    }
                    ForEach(sessions) { session in
                        NavigationLink {
                            SavedMeetingDetail(session: session)
                                .toolbar {
                                    ShareLink(item: ExportDocument(sessions: [session]),
                                        preview: SharePreview("Graption meeting")) {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(session.displayTitle)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                Text("\(session.captions.count) captions")
                                    .font(.subheadline)
                            }
                        }
                        .swipeActions {
                            if session.id != activeSessionID {
                                Button("Delete", role: .destructive) { deleting = session }
                            }
                            Button("Rename") {
                                meetingTitle = session.title ?? ""
                                renaming = session
                            }
                            .tint(.blue)
                        }
                    }
                    Button("Reload Saved Sessions") {
                        Task { await reload() }
                    }
                }
                Section("Retention") {
                    Picker("Keep meetings", selection: $retentionDays) {
                        Text("Forever").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    Text("Older meetings are removed from this iPhone. Deletions reach the server on the next sync. Active meetings are kept.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Saved sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !sessions.isEmpty {
                        ShareLink(item: ExportDocument(sessions: sessions), preview: SharePreview("Graption meetings")) { Label("Export all", systemImage: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                store = try FileSessionStore.onDevice()
                await reload()
            } catch {
                errorMessage = "Could not open local session storage. \(error.localizedDescription)"
            }
        }
        .onChange(of: retentionDays) { _, _ in Task { await reload() } }
        .alert("Rename meeting", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Meeting name", text: $meetingTitle)
            Button("Save") {
                guard let id = renaming?.id, let store else { return }
                Task {
                    do { try await store.rename(id, title: meetingTitle); await reload() }
                    catch { errorMessage = error.localizedDescription }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete this meeting from the iPhone and server?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete meeting", role: .destructive) {
                guard let id = deleting?.id, let store else { return }
                Task {
                    do { try await store.delete(id); await reload() }
                    catch { errorMessage = error.localizedDescription }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .alert("Session storage", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        guard let store else { return }
        do {
            if retentionDays > 0 {
                try await store.prune(olderThan: Date().addingTimeInterval(-Double(retentionDays) * 86400),
                    excluding: activeSessionID)
            }
            sessions = try await store.loadSessions()
        } catch {
            errorMessage = "Could not load saved sessions. \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private func startFakeSession() {
        guard let store else { return }
        let recorder = SessionRecorder(store: store)
        let versions = ["asr": "fake-asr-v1", "asd": "fake-asd-v1"]
        recorder.append(SavedCaption(text: "Hello, everyone.", speakerID: "f1",
            toneTag: "happy", tStart: 0, tEnd: 2,
            modelVersions: versions.merging(["tone": "fake-tone-v1"]) { _, new in new }))
        recorder.append(SavedCaption(text: "Let's plan our next meeting.", speakerID: "f2",
            tStart: 2.5, tEnd: 5, modelVersions: versions))
        recorder.append(SavedCaption(text: "See you on Friday!", speakerID: "unknown",
            tStart: 5.5, tEnd: 7, modelVersions: versions))
        self.recorder = recorder
    }

    private func endSession() async {
        guard let recorder else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await recorder.end()
            self.recorder = nil
            await reload()
        } catch {
            errorMessage = "Could not save this session. Tap End Session & Save to retry. \(error.localizedDescription)"
        }
    }
    #endif
}

private struct SavedMeetingDetail: View {
    let session: SavedSession

    var body: some View {
        List {
            Section("Transcript") {
                ForEach(session.captions) { CaptionRow(caption: $0) }
            }
            Section("Sound alerts") {
                if (session.soundEvents ?? []).isEmpty { Text("No saved sound alerts.") }
                ForEach(session.soundEvents ?? []) { event in
                    VStack(alignment: .leading) {
                        Text(event.label).font(.headline)
                        Text("\(event.t.formatted()) seconds · \(event.confidence.formatted(.percent)) confidence")
                        Text(event.modelVersion).font(.caption)
                    }
                }
            }
        }
        .navigationTitle(session.displayTitle)
    }
}

private struct CaptionRow: View {
    let caption: SavedCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(speakerLabel(caption.speakerID))
                .font(.headline)
                .foregroundStyle(colorForSpeaker(caption.speakerID))
            Text(caption.text)
            if let tone = caption.toneTag {
                Text("Tone: \(tone)")
                    .font(.subheadline)
            }
            if let probs = caption.toneProbs {
                ForEach(probs.keys.sorted(), id: \.self) { emotion in
                    Text("\(emotion): \((probs[emotion] ?? 0).formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                }
            }
            if let scores = caption.toneScores {
                ForEach(scores.keys.sorted(), id: \.self) { dimension in
                    Text("\(dimension): \((scores[dimension] ?? 0).formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                }
            }
            Text("\(caption.tStart.formatted())–\(caption.tEnd.formatted()) seconds")
                .font(.caption)
        }
    }
}

#Preview {
    ContentView()
}

private struct ExportDocument: Transferable {
    let sessions: [SavedSession]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { document in
            let data = try SessionExport.encode(document.sessions, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("graption-meetings-\(formatter.string(from: Date())).json")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
