import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Bindable var model: DictationModel
    @State private var showSettings = false

    private var engine: SpeechEngine { model.engine }
    private var accent: Color { Color(red: 0.38, green: 0.84, blue: 0.72) }

    /// En macOS el editor no tiene inset superior; en iOS sí.
    private var placeholderTopPadding: CGFloat {
        #if os(macOS)
        0
        #else
        8
        #endif
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 14) {
                header
                draftCard
                statusLine
                controls
                recentSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 6)

            toast
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .animation(.spring(duration: 0.3), value: model.history.entries)
        .animation(.spring(duration: 0.3), value: engine.errorMessage)
        .animation(.spring(duration: 0.25), value: model.copiedAt)
    }

    // MARK: - Secciones

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PromptVoice")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(model.activeLocale.language.languageCode?.identifier.uppercased() ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.draft)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.95))
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty && !engine.isActive {
                        Text("Toca el micrófono y dicta tu prompt…")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(.top, placeholderTopPadding)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            if engine.isActive && !engine.displayText.isEmpty {
                liveText
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            engine.isRecording ? accent.opacity(0.5) : .white.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
    }

    private var liveText: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(engine.displayText)
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let message = engine.errorMessage {
            Button {
                engine.errorMessage = nil
            } label: {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.red.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text(statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .frame(height: 18)
        }
    }

    private var statusText: String {
        switch engine.phase {
        case .idle:
            #if os(macOS)
            return "Listo · \(model.hotKey.displayString) para dictar · \(languageName)"
            #else
            return "Listo · \(languageName)"
            #endif
        case .preparing:
            return "Preparando modelo…"
        case .recording:
            return "Escuchando…"
        case .finishing:
            return "Terminando…"
        }
    }

    private var languageName: String {
        model.activeLocale.localizedString(forIdentifier: model.activeLocale.identifier) ?? ""
    }

    private var controls: some View {
        HStack(spacing: 26) {
            actionButton(
                icon: "trash",
                help: "Limpiar",
                disabled: model.draft.isEmpty && !engine.isActive
            ) {
                model.clear()
            }

            micButton

            actionButton(
                icon: model.copiedAt == nil ? "doc.on.doc" : "checkmark",
                help: "Copiar",
                tint: model.copiedAt == nil ? nil : accent,
                disabled: !model.canCopy
            ) {
                model.copyDraft()
            }
        }
    }

    private var micButton: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 2)
                    .scaleEffect(1.25 + engine.level * 0.35)
                    .opacity(engine.isRecording ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: engine.level)

                Circle()
                    .fill(engine.isRecording ? accent : .white)
                    .frame(width: 76, height: 76)
                    .shadow(color: accent.opacity(engine.isRecording ? 0.5 : 0.15), radius: 24)

                if engine.isBusy {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: engine.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 96, height: 96)
            .scaleEffect(engine.isRecording ? 1 + engine.level * 0.06 : 1)
            .animation(.spring(duration: 0.25), value: engine.isRecording)
            .animation(.easeOut(duration: 0.12), value: engine.level)
        }
        .buttonStyle(.plain)
        .disabled(engine.isBusy)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(engine.isRecording ? "Detener" : "Grabar")
    }

    private func actionButton(
        icon: String,
        help: String,
        tint: Color? = nil,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(disabled ? .white.opacity(0.18) : (tint ?? .white.opacity(0.65)))
                .frame(width: 52, height: 52)
                .background(.white.opacity(disabled ? 0.03 : 0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.history.entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recientes")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))

                    Spacer()

                    Button("Borrar todo") {
                        model.history.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.history.entries.prefix(6)) { entry in
                            Button {
                                model.use(entry)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(entry.text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Spacer(minLength: 0)

                                    Text(entry.date, format: .dateTime.hour().minute())
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.22))
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 12)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Borrar", role: .destructive) {
                                    model.history.remove(entry)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: 160)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if model.copiedAt != nil {
            VStack {
                Spacer()
                Label("Copiado al portapapeles", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(accent, in: Capsule())
                    .padding(.bottom, 130)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.13), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Platform.dismissKeyboard()
        }
    }
}

struct SettingsView: View {
    @Bindable var model: DictationModel
    @Environment(\.dismiss) private var dismiss

    private let languages: [(String, String)] = [
        ("", "Sistema"),
        ("es-ES", "Español (España)"),
        ("es-MX", "Español (México)"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("ca-ES", "Català"),
        ("fr-FR", "Français"),
        ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"),
        ("pt-BR", "Português (Brasil)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Dictado") {
                    Picker("Idioma", selection: $model.localeID) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    Toggle("Copiar al terminar", isOn: $model.autoCopy)
                    Toggle("Vaciar el borrador al terminar", isOn: $model.clearAfterDictation)
                    Text("Un dictado = un prompt: el cuadro queda limpio para el siguiente. El texto sigue en el portapapeles y en Recientes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if os(macOS)
                Section("Atajo global") {
                    HStack {
                        Text("Combinación")
                        Spacer()
                        Button {
                            capturingHotKey ? stopCapture() : startCapture()
                        } label: {
                            Text(capturingHotKey ? "Pulsa la combinación…" : model.hotKey.displayString)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }

                    if capturingHotKey {
                        Text("Pulsa ⌘, ⌥ o ⌃ junto con una tecla. Esc para cancelar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let error = model.hotKeyError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Restaurar ⌥Espacio") {
                        model.hotKey = .default
                    }
                }

                Section("Automatización") {
                    Toggle("Pegar automáticamente en la app activa", isOn: $model.autoPaste)
                    Text("El texto se pega en la app que esté delante (tu agente) sin cambiar de ventana.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !Paste.isTrusted {
                        Button("Conceder permiso de Accesibilidad…") {
                            Paste.requestAccess()
                        }
                        Text("Necesario solo para el pegado automático. macOS lo pedirá en Ajustes > Privacidad y seguridad > Accesibilidad.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 420, height: 430)
        .onDisappear { stopCapture() }
        #endif
    }

    #if os(macOS)
    @State private var capturingHotKey = false
    @State private var keyMonitor: Any?

    private func startCapture() {
        guard keyMonitor == nil else { return }
        capturingHotKey = true
        model.hotKeyError = nil

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopCapture()
                return nil
            }

            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= HotKeyModifier.command.rawValue }
            if event.modifierFlags.contains(.option) { modifiers |= HotKeyModifier.option.rawValue }
            if event.modifierFlags.contains(.control) { modifiers |= HotKeyModifier.control.rawValue }
            if event.modifierFlags.contains(.shift) { modifiers |= HotKeyModifier.shift.rawValue }

            guard modifiers & HotKeyModifier.essential != 0 else {
                NSSound.beep()
                return nil
            }

            model.hotKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        capturingHotKey = false
    }
    #endif
}
