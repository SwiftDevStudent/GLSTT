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
                ForEach(appModel.transcriptHistory) { entry in
                    NavigationLink(value: entry) {
                        PhoneTranscriptRow(entry: entry)
                    }
                }
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
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") {
                    appModel.copyTranscript(entry.text)
                }
            }
        }
    }
}
#endif
