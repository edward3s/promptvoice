import Foundation
import Observation

#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class DictationModel {
    static let shared = DictationModel()

    let engine = SpeechEngine()
    let history = HistoryStore()

    var draft = ""
    var copiedAt: Date?

    var localeID: String {
        didSet { defaults.set(localeID, forKey: Keys.localeID) }
    }
    var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) }
    }
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }
    /// Vaciar el borrador al terminar cada dictado (un dictado = un prompt).
    var clearAfterDictation: Bool {
        didSet { defaults.set(clearAfterDictation, forKey: Keys.clearAfterDictation) }
    }

    /// Atajo global para empezar/parar el dictado (solo macOS).
    var hotKey: HotKey {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
            #if os(macOS)
            hotKeyError = GlobalHotKey.shared.register(hotKey)
            #endif
        }
    }
    var hotKeyError: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let localeID = "localeID"
        static let autoCopy = "autoCopy"
        static let autoPaste = "autoPaste"
        static let clearAfterDictation = "clearAfterDictation"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }

    private init() {
        localeID = defaults.string(forKey: Keys.localeID) ?? ""
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        clearAfterDictation = defaults.object(forKey: Keys.clearAfterDictation) as? Bool ?? true

        if let keyCode = defaults.object(forKey: Keys.hotKeyKeyCode) as? Int,
           let modifiers = defaults.object(forKey: Keys.hotKeyModifiers) as? Int {
            hotKey = HotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        } else {
            hotKey = .default
        }
    }

    var activeLocale: Locale {
        localeID.isEmpty ? Locale.current : Locale(identifier: localeID)
    }

    var canCopy: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Acciones

    func toggle() async {
        if engine.isRecording {
            await finish()
        } else if !engine.isBusy {
            Platform.startFeedback()
            await engine.start(localeIdentifier: activeLocale.identifier)
        }
    }

    func finish() async {
        let text = await engine.stop()
        guard !text.isEmpty else { return }

        history.add(text)
        Platform.stopFeedback()

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmed.isEmpty ? text : trimmed + " " + text

        // El texto tiene que acabar en el portapapeles si se va a pegar (automática o manualmente).
        let delivers = autoCopy || autoPaste
        if delivers {
            copy(prompt, feedback: false)
        }

        #if os(macOS)
        if autoPaste, !NSApp.isActive, Paste.isTrusted {
            try? await Task.sleep(for: .milliseconds(120))
            Paste.sendCommandV()
        }
        #endif

        // Un dictado = un prompt: si ya se ha entregado, dejamos el cuadro limpio
        // para que el siguiente dictado no se concatene con el anterior.
        draft = (clearAfterDictation && delivers) ? "" : prompt
    }

    func copy(_ text: String, feedback: Bool = true) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        Platform.copyToClipboard(clean)
        if feedback { Platform.successFeedback() }

        let stamp = Date()
        copiedAt = stamp

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard copiedAt == stamp else { return }
            copiedAt = nil
        }
    }

    func clear() {
        draft = ""
        engine.errorMessage = nil
    }

    func use(_ entry: HistoryEntry) {
        draft = entry.text
        copy(entry.text)
    }

    func copyDraft() {
        copy(draft)
    }
}
