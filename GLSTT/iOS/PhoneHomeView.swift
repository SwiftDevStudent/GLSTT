#if os(iOS)
import SwiftUI

struct PhoneHomeView: View {
    @Environment(PhoneAppModel.self) private var appModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                PhoneComposerSection()
                    .environment(appModel)

                PhoneTranscriptHistorySection()
                    .environment(appModel)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("GLSTT")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TranscriptHistoryEntry.self) { entry in
                PhoneTranscriptDetailView(entry: entry)
                    .environment(appModel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    PhoneSettingsView()
                        .environment(appModel)
                }
            }
        }
        .tint(.orange)
        .task {
            appModel.refreshPermissions()
        }
        .alert("GLSTT", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) {
                appModel.alertMessage = nil
            }
        } message: {
            Text(appModel.alertMessage ?? "")
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { appModel.alertMessage != nil },
            set: { newValue in
                if !newValue {
                    appModel.alertMessage = nil
                }
            }
        )
    }
}
#endif
