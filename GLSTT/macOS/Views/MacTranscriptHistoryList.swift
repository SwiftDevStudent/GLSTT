#if os(macOS)
import SwiftUI

struct MacTranscriptHistoryList: View {
    let entries: [TranscriptHistoryEntry]
    let emptyTitle: String
    let emptyMessage: String
    let compact: Bool
    let copy: (TranscriptHistoryEntry) -> Void
    let latestAlwaysExpanded: Bool

    @State private var expandedEntryIDs = Set<TranscriptHistoryEntry.ID>()

    init(
        entries: [TranscriptHistoryEntry],
        emptyTitle: String = "No transcripts yet",
        emptyMessage: String,
        compact: Bool = false,
        latestAlwaysExpanded: Bool = true,
        copy: @escaping (TranscriptHistoryEntry) -> Void = { _ in }
    ) {
        self.entries = entries
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.compact = compact
        self.copy = copy
        self.latestAlwaysExpanded = latestAlwaysExpanded
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "waveform.badge.mic",
                description: Text(emptyMessage)
            )
            .frame(maxWidth: .infinity, minHeight: compact ? 120 : 220)
        } else {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                ForEach(entries) { entry in
                    MacTranscriptHistoryDisclosureRow(
                        entry: entry,
                        isExpanded: isExpanded(entry),
                        canToggle: canToggle(entry),
                        compact: compact,
                        copy: {
                            copy(entry)
                        }
                    ) {
                        toggle(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear(perform: expandLatestEntry)
            .onChange(of: entries.first?.id) { _, _ in
                expandLatestEntry()
            }
        }
    }

    private func isExpanded(_ entry: TranscriptHistoryEntry) -> Bool {
        if latestAlwaysExpanded, entry.id == entries.first?.id {
            return true
        }

        return expandedEntryIDs.contains(entry.id)
    }

    private func canToggle(_ entry: TranscriptHistoryEntry) -> Bool {
        !(latestAlwaysExpanded && entry.id == entries.first?.id)
    }

    private func toggle(_ entry: TranscriptHistoryEntry) {
        guard canToggle(entry) else { return }

        if expandedEntryIDs.contains(entry.id) {
            expandedEntryIDs.remove(entry.id)
        } else {
            expandedEntryIDs.insert(entry.id)
        }
    }

    private func expandLatestEntry() {
        guard latestAlwaysExpanded, let id = entries.first?.id else { return }
        expandedEntryIDs.insert(id)
    }
}

private struct MacTranscriptHistoryDisclosureRow: View {
    let entry: TranscriptHistoryEntry
    let isExpanded: Bool
    let canToggle: Bool
    let compact: Bool
    let copy: () -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(compact ? .subheadline : .body, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                if canToggle {
                    Button(action: toggle) {
                        Label(isExpanded ? "Hide" : "Show", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded {
                Text(entry.text)
                    .font(.system(compact ? .caption : .body, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(compact ? 6 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
#endif
