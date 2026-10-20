#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Foundation

/// Atajo global configurable que funciona aunque la app no tenga el foco.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Registra la combinación. Devuelve un mensaje de error si no se pudo.
    @discardableResult
    func register(_ hotKey: HotKey) -> String? {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50564F49), id: 1) // 'PVOI'
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            return "No se pudo registrar \(hotKey.displayString). Puede estar en uso por otra app."
        }
        hotKeyRef = ref
        return nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<GlobalHotKey>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .onTrigger?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

enum Paste {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let key: CGKeyCode = 9 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKey.shared.onTrigger = {
            Task { @MainActor in
                await DictationModel.shared.toggle()
            }
        }

        Task { @MainActor in
            let model = DictationModel.shared
            model.hotKeyError = GlobalHotKey.shared.register(model.hotKey)
            if let error = model.hotKeyError {
                print("PromptVoice: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif
