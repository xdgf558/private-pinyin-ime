import SwiftUI

struct ContentView: View {
    @State private var statusText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard") {
                    Text("Enable PrivatePinyin from Settings > General > Keyboard > Keyboards.")
                    Text("Full Access is off by default.")
                }

                Section("Privacy") {
                    Button("Clear Local Lexicon") {
                        clearLocalLexicon()
                    }
                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("PrivatePinyin")
        }
    }

    private func clearLocalLexicon() {
        do {
            let removed = try IosSettingsStore.clearLocalLexiconArtifacts()
            statusText = removed == 0 ? "No local lexicon files found." : "Local lexicon cleared."
        } catch {
            statusText = "Could not clear local lexicon."
        }
    }
}

#Preview {
    ContentView()
}
