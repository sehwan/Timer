import Cocoa
import Carbon.HIToolbox

class TimerAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var seconds: Int = 0
    var isRunning: Bool = false
    var hotKeyRef: EventHotKeyRef? = nil
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        seconds = UserDefaults.standard.integer(forKey: "savedSeconds")
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemUI()
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "시작/정지 (Shift+Ctrl+S)", action: #selector(toggleAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "초기화", action: #selector(resetTimer), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        setupCarbonHotkey()
    }
    
    @objc func toggleAction() {
        toggleTimer()
    }
    
    @objc func resetTimer() {
        seconds = 0
        UserDefaults.standard.set(seconds, forKey: "savedSeconds")
        updateStatusItemUI()
    }
    
    func setupCarbonHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(fourCharCode: "TIMR")
        hotKeyID.id = UInt32(1)
        
        // Shift (shiftKey) + Control (controlKey) + S (kVK_ANSI_S = 1)
        let keyCode: UInt32 = 1 
        let modifiers: UInt32 = UInt32(shiftKey | controlKey)
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            if let ptr = userData {
                let delegate = Unmanaged<TimerAppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.toggleTimer()
                }
            }
            return noErr
        }, 1, &eventType, ptr, nil)
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func toggleTimer() {
        isRunning.toggle()
        if isRunning {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.seconds += 1
                UserDefaults.standard.set(self.seconds, forKey: "savedSeconds")
                self.updateStatusItemUI()
            }
            RunLoop.current.add(timer!, forMode: .common)
            updateStatusItemUI()
        } else {
            timer?.invalidate()
            timer = nil
            updateStatusItemUI()
        }
    }
    
    func updateStatusItemUI() {
        if let button = statusItem.button {
            let timeString = formatTime(seconds)
            let color = isRunning ? NSColor.systemRed : NSColor.systemGray
            
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            ]
            let attributedTitle = NSAttributedString(string: timeString, attributes: attributes)
            button.attributedTitle = attributedTitle
        }
    }
    
    func formatTime(_ totalSeconds: Int) -> String {
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        let h = totalSeconds / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

extension OSType {
    init(fourCharCode: String) {
        var value: UInt32 = 0
        for char in fourCharCode.utf16 {
            value = (value << 8) + UInt32(char)
        }
        self = value
    }
}

let app = NSApplication.shared
let delegate = TimerAppDelegate()
app.delegate = delegate
app.run()
