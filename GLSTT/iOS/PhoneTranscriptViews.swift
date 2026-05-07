#if os(iOS)
import SwiftUI

struct PhoneTranscriptHistorySection: View {
    @Environment(PhoneAppModel.self) private var appModel
    @State private var expandedEntryIDs = Set<TranscriptHistoryEntry.ID>()

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
                    PhoneTranscriptCard(
                        entry: entry,
                        isExpanded: expandedEntryIDs.contains(entry.id),
                        copy: {
                            appModel.copyTranscript(entry.text)
                        },
                        toggle: {
                            toggle(entry)
                        }
                    )
                }
            }
        }
    }

    private func toggle(_ entry: TranscriptHistoryEntry) {
        if expandedEntryIDs.contains(entry.id) {
            expandedEntryIDs.remove(entry.id)
        } else {
            expandedEntryIDs.insert(entry.id)
        }
    }
}

private struct PhoneTranscriptCard: View {
    let entry: TranscriptHistoryEntry
    let isExpanded: Bool
    let copy: () -> Void
    let toggle: () -> Void

    @State private var copied = false
    private let collapsedLineLimit = 7
    private let expansionCharacterThreshold = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            footer
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: copyWithFeedback) {
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .contentTransition(.opacity)

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if canExpand {
                Button(action: toggle) {
                    Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Collapse transcript" : "Expand transcript")
            }
        }
    }

    private var canExpand: Bool {
        entry.text.count > expansionCharacterThreshold || entry.text.filter(\.isNewline).count >= collapsedLineLimit
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
