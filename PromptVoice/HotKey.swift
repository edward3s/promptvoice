import Foundation

#if os(macOS)
import Carbon.HIToolbox
#endif

/// Modificadores con los mismos valores que usa Carbon para registrar el atajo.
enum HotKeyModifier: UInt32 {
    case command = 256   // cmdKey
    case shift = 512     // shiftKey
    case option = 2048   // optionKey
    case control = 4096  // controlKey

    static let essential: UInt32 = command.rawValue | option.rawValue | control.rawValue
}

struct HotKey: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKey(keyCode: 49, modifiers: HotKeyModifier.option.rawValue)

    var displayString: String {
        var text = ""
        if modifiers & HotKeyModifier.control.rawValue != 0 { text += "⌃" }
        if modifiers & HotKeyModifier.option.rawValue != 0 { text += "⌥" }
        if modifiers & HotKeyModifier.shift.rawValue != 0 { text += "⇧" }
        if modifiers & HotKeyModifier.command.rawValue != 0 { text += "⌘" }
        return text + keyName
    }

    private var keyName: String {
        switch Int(keyCode) {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Espacio"
        case 51: return "⌫"
        case 53: return "Esc"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: break
        }

        #if os(macOS)
        let character = Self.layoutCharacter(for: keyCode)
        return character.isEmpty ? "Tecla \(keyCode)" : character.uppercased()
        #else
        return "Tecla \(keyCode)"
        #endif
    }

    #if os(macOS)
    /// Nombre de la tecla según la distribución de teclado activa.
    static func layoutCharacter(for keyCode: UInt32) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "" }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: characters, count: length)
    }
    #endif
}
