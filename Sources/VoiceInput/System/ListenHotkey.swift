import AppKit
import os.log

/// Global Fn+Space hotkey toggling Live Captions.
///
/// A dedicated CGEventTap (separate from KeyMonitor's dictation state machine):
/// keyDown with the secondary-Fn flag and the Space keycode fires the callback
/// and swallows the event so a space character never reaches the focused app.
/// NSEvent global monitor is the no-Accessibility fallback (cannot swallow).
final class ListenHotkey {
    var onToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?

    private static let spaceKeyCode: Int64 = 49

    func start() {
        stop()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ListenHotkey>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown,
                  event.getIntegerValueField(.keyboardEventKeycode) == ListenHotkey.spaceKeyCode,
                  event.flags.contains(.maskSecondaryFn),
                  // Bare Fn+Space only — don't hijack ⌘Fn+Space etc.
                  !event.flags.contains(.maskCommand),
                  !event.flags.contains(.maskAlternate),
                  !event.flags.contains(.maskControl),
                  !event.flags.contains(.maskShift)
            else { return Unmanaged.passUnretained(event) }

            DispatchQueue.main.async { monitor.onToggle?() }
            return nil   // swallow
        }

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.keys.info("ListenHotkey tap installed (Fn+Space)")
        } else {
            // Accessibility not granted (yet): observe-only fallback.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == UInt16(ListenHotkey.spaceKeyCode),
                      event.modifierFlags.contains(.function),
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                else { return }
                self?.onToggle?()
            }
            Log.keys.warning("ListenHotkey using NSEvent fallback (no event tap)")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
