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

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let localeID = "localeID"
        static let autoCopy = "autoCopy"
        static let autoPaste = "autoPaste"
    }

    private init() {
        localeID = defaults.string(forKey: Keys.localeID) ?? ""
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
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

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? text : trimmed + " " + text
        history.add(text)
        Platform.stopFeedback()

        if autoCopy {
            copy(draft, feedback: false)
        }

        #if os(macOS)
        if autoPaste, !NSApp.isActive, Paste.isTrusted {
            try? await Task.sleep(for: .milliseconds(120))
            Paste.sendCommandV()
        }
        #endif
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
