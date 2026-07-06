import SwiftUI

struct ContentView: View {
    @State private var statusText = ""
    @State private var learningEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard") {
                    Text("Enable PrivatePinyin from Settings > General > Keyboard > Keyboards.")
                    Text("Full Access stays off by default; the keyboard does not use network APIs.")
                }

                Section("Privacy") {
                    Text("User learning is off until enabled here. Learned entries store only selected phrase, pinyin, frequency, and update time.")
                    Text(IosSettingsStore.storageDescription())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Learn selected candidates", isOn: Binding(
                        get: { learningEnabled },
                        set: { setLearningEnabled($0) }
                    ))
                    .disabled(!IosSettingsStore.usesAppGroupStorage)
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
            .onAppear {
                _ = IosSettingsStore.ensureSettingsFile()
                learningEnabled = IosSettingsStore.isLearningEnabled()
            }
        }
    }

    private func setLearningEnabled(_ enabled: Bool) {
        if IosSettingsStore.setLearningEnabled(enabled) {
            learningEnabled = enabled
            statusText = enabled ? "User learning enabled." : "User learning disabled."
        } else {
            learningEnabled = IosSettingsStore.isLearningEnabled()
            statusText = "Could not update learning setting."
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
