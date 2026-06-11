import AppKit
import Carbon

/// Injects transcribed text into the focused application using clipboard +
/// synthetic Cmd-V. Handles non-ASCII IME sources (e.g. Chinese Pinyin) by
/// briefly switching to an ASCII-capable layout before pasting, then restoring
/// the original source after 300 ms — matching the old app's proven timing.
///
/// The transcribed text is intentionally left on the clipboard as a fallback:
/// if Accessibility is not granted the Cmd-V simulation is a no-op, but the
/// user can still manually paste.
final class TextInjector {

    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // If a non-ASCII input source (e.g. Chinese IME) is active, temporarily
        // switch to an ASCII-capable one so Cmd-V is not intercepted by the IME.
        let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let needSwitch = !isASCIICapable(originalSource)

        if needSwitch {
            if let asciiSource = findASCIICapableSource() {
                TISSelectInputSource(asciiSource)
                usleep(50_000) // 50 ms for system to settle
            }
        }

        // Synthesise Cmd+V (requires Accessibility permission).
        let source   = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)

        Log.keys.info("TextInjector: injected \(text.count) chars needSwitch=\(needSwitch)")

        // Restore input source after paste.
        if needSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                TISSelectInputSource(originalSource)
            }
        }
    }

    // MARK: - Input-source helpers

    private func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func findASCIICapableSource() -> TISInputSource? {
        let criteria = [
            kTISPropertyInputSourceIsASCIICapable: true,
            kTISPropertyInputSourceIsEnabled: true
        ] as CFDictionary
        guard let sourceList = TISCreateInputSourceList(criteria, false)?
            .takeRetainedValue() as? [TISInputSource]
        else { return nil }

        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US" {
                    return source
                }
            }
        }
        return sourceList.first
    }
}
