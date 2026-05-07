#if os(iOS)
import SwiftUI

struct PhoneTranscriptHistorySection: View {
    @Environment(PhoneAppModel.self) private var appModel

    var body: some View {
        Section("Recent Transcripts") {
            if appModel.transcriptHistory.isEmpty {
                ContentUnavailableView(
                    "No transcripts yet",
                    systemImage: "text.bubble",
                    description: Text("Tap the microphone to transcribe directly into the note above.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .listRowBackground(Color.clear)
            } else {
                if let latestEntry = appModel.transcriptHistory.first {
                    PhoneLatestTranscriptCard(entry: latestEntry) {
                        appModel.copyTranscript(latestEntry.text)
                    }
                }

                ForEach(appModel.transcriptHistory.dropFirst()) { entry in
                    NavigationLink(value: entry) {
                        PhoneTranscriptRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct PhoneLatestTranscriptCard: View {
    let entry: TranscriptHistoryEntry
    let copy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copyWithFeedback) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? .green : .accentColor)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.borderless)
            }

            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func copyWithFeedback() {
        copy()

        withAnimation(.snappy(duration: 0.18)) {
            copied = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy(duration: 0.18)) {
                copied = false
            }
        }
    }
}

private struct PhoneTranscriptRow: View {
    let entry: TranscriptHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)

            Text(entry.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct PhoneTranscriptDetailView: View {
    let entry: TranscriptHistoryEntry
    @Environment(PhoneAppModel.self) private var appModel
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(entry.timestamp.formatted(date: .complete, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: copyWithFeedback) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private func copyWithFeedback() {
        appModel.copyTranscript(entry.text)

        withAnimation(.snappy(duration: 0.18)) {
            copied = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy(duration: 0.18)) {
                copied = false
            }
        }
    }
}
#endif
