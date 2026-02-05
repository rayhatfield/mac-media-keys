import Cocoa
import CoreGraphics

// Media key codes from IOKit/hidsystem/ev_keymap.h
enum MediaKey: Int32 {
    case play = 16        // NX_KEYTYPE_PLAY
    case next = 17        // NX_KEYTYPE_NEXT
    case previous = 18    // NX_KEYTYPE_PREVIOUS
    case fast = 19        // NX_KEYTYPE_FAST
    case rewind = 20      // NX_KEYTYPE_REWIND
}

protocol MediaKeyTapDelegate: AnyObject {
    func mediaKeyTap(_ tap: MediaKeyTap, receivedKey key: MediaKey)
}

class MediaKeyTap {
    weak var delegate: MediaKeyTapDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {}

    deinit {
        stop()
    }

    // MARK: - Accessibility Permission

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Event Tap Management

    func start() -> Bool {
        let trusted = Self.isAccessibilityEnabled()
        NSLog("MediaKeyTap: Accessibility trusted = \(trusted)")

        guard trusted else {
            NSLog("MediaKeyTap: Accessibility permission not granted")
            return false
        }

        // Create event tap for system-defined events (which include media keys)
        // NX_SYSDEFINED = 14, this is where media keys come through
        let eventMask: CGEventMask = CGEventMask(1 << 14)  // Only NX_SYSDEFINED events
        NSLog("MediaKeyTap: Creating event tap with mask: \(eventMask)")

        // Use a static callback that will call our instance method
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            NSLog("MediaKeyTap: Failed to create event tap. CGEvent.tapCreate returned nil.")
            NSLog("MediaKeyTap: This usually means accessibility permission is not granted or the app needs to be re-authorized.")
            return false
        }
        NSLog("MediaKeyTap: Event tap created successfully")

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        guard let runLoopSource = runLoopSource else {
            print("Failed to create run loop source")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        NSLog("MediaKeyTap: Event tap enabled and added to run loop")
        return true
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events (re-enable if needed)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Convert to NSEvent to check for media keys
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        // Media keys come as system-defined events with subtype 8
        guard nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        // Extract key code and key state from data1
        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let keyRepeat = keyFlags & 0x1

        // Check if it's a media key we care about
        guard MediaKey(rawValue: keyCode) != nil else {
            return Unmanaged.passUnretained(event)
        }

        // Key states: 0xA = key down, 0xB = key up
        // We MUST consume BOTH to prevent the system from seeing a complete keypress
        // which would trigger mediaremoted to launch Apple Music

        if keyState == 0xA {
            // Key down event
            if keyRepeat == 0 {
                // Only notify delegate on first key down (not repeats)
                if let mediaKey = MediaKey(rawValue: keyCode) {
                    NSLog("MediaKeyTap: Key DOWN - \(mediaKey)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.mediaKeyTap(self, receivedKey: mediaKey)
                    }
                }
            }
            // Consume key down
            return nil
        } else if keyState == 0xB {
            // Key up event - consume but don't notify
            NSLog("MediaKeyTap: Key UP - consuming")
            return nil
        }

        // Pass through other events
        return Unmanaged.passUnretained(event)
    }
}
