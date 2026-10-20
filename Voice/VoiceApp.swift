import SwiftUI

@main
struct VoiceApp: App {
    @State private var model = DictationModel.shared

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup("Voice") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(
                    minWidth: 380, idealWidth: 420, maxWidth: .infinity,
                    minHeight: 540, idealHeight: 660, maxHeight: .infinity
                )
                #endif
        }
        #if os(macOS)
        MenuBarExtra {
            Button(model.engine.isRecording ? "Detener dictado" : "Empezar dictado") {
                Task { await model.toggle() }
            }
            .disabled(model.engine.isBusy)

            Button("Copiar borrador") {
                model.copyDraft()
            }
            .disabled(!model.canCopy)

            Divider()

            Button("Abrir Voice") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
            }

            Button("Salir") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: model.engine.isRecording ? "waveform" : "mic")
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}
