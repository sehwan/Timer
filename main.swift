import Cocoa
import Carbon.HIToolbox

class TimerAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var seconds: Int = 0
    var isRunning: Bool = false
    var midnightOffset: Int = 0
    var lastActiveDay: String = ""
    var hotKeyRef: EventHotKeyRef? = nil
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        midnightOffset = UserDefaults.standard.integer(forKey: "midnightOffset")
        lastActiveDay = UserDefaults.standard.string(forKey: "lastActiveDay") ?? currentDateString()
        seconds = UserDefaults.standard.integer(forKey: "savedSeconds")
        
        if lastActiveDay != currentDateString() {
            seconds = 0
            lastActiveDay = currentDateString()
            UserDefaults.standard.set(lastActiveDay, forKey: "lastActiveDay")
            UserDefaults.standard.set(seconds, forKey: "savedSeconds")
        }
        
        var dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
        if dailyRecords[lastActiveDay] == nil {
            dailyRecords[lastActiveDay] = seconds
            UserDefaults.standard.set(dailyRecords, forKey: "dailyRecords")
        } else if let saved = dailyRecords[lastActiveDay], seconds == 0 && saved > 0 {
            seconds = saved
        }
        
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemUI()
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        startTimer()
        setupCarbonHotkey()
    }
    
    @objc func toggleAction() {
        toggleTimer()
    }
    
    @objc func resetTimer() {
        seconds = 0
        UserDefaults.standard.set(seconds, forKey: "savedSeconds")
        
        let currentDay = currentDateString()
        var dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
        dailyRecords[currentDay] = 0
        UserDefaults.standard.set(dailyRecords, forKey: "dailyRecords")
        
        updateStatusItemUI()
    }
    
    func currentDateString() -> String {
        let logicalDate = Date().addingTimeInterval(-Double(midnightOffset))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: logicalDate)
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        menu.addItem(NSMenuItem(title: "시작/정지 (Shift+Ctrl+S)", action: #selector(toggleAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "초기화", action: #selector(resetTimer), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "하루의 마무리 +1시간", action: #selector(addMidnightOffset), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "하루의 마무리 -1시간", action: #selector(subMidnightOffset), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "하루의 마무리 초기화", action: #selector(resetMidnightOffset), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        let historyItem = NSMenuItem(title: "📋 최근 7일 기록", action: nil, keyEquivalent: "")
        historyItem.isEnabled = false
        menu.addItem(historyItem)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let logicalNow = Date().addingTimeInterval(-Double(midnightOffset))
        
        var totalSeconds = 0
        let dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
        
        for i in (1...7).reversed() {
            if let pastDate = Calendar.current.date(byAdding: .day, value: -i, to: logicalNow) {
                let dateString = formatter.string(from: pastDate)
                let secs = dailyRecords[dateString] ?? 0
                
                let timeStr = formatTime(secs)
                let item = NSMenuItem(title: "\(i) days ago: \(timeStr)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
                
                totalSeconds += secs
            }
        }
        
        let avgSeconds = totalSeconds / 7
        menu.addItem(NSMenuItem.separator())
        let avgItem = NSMenuItem(title: "📊 7일 평균: \(formatTime(avgSeconds))", action: nil, keyEquivalent: "")
        avgItem.isEnabled = false
        menu.addItem(avgItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    @objc func addMidnightOffset() {
        midnightOffset += 3600
        UserDefaults.standard.set(midnightOffset, forKey: "midnightOffset")
        updateStatusItemUI()
    }
    
    @objc func subMidnightOffset() {
        midnightOffset -= 3600
        UserDefaults.standard.set(midnightOffset, forKey: "midnightOffset")
        updateStatusItemUI()
    }
    
    @objc func resetMidnightOffset() {
        midnightOffset = 0
        UserDefaults.standard.set(midnightOffset, forKey: "midnightOffset")
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
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentDay = self.currentDateString()
            if currentDay != self.lastActiveDay {
                self.lastActiveDay = currentDay
                self.seconds = 0
                UserDefaults.standard.set(self.lastActiveDay, forKey: "lastActiveDay")
                UserDefaults.standard.set(self.seconds, forKey: "savedSeconds")
            }
            
            if self.isRunning {
                self.seconds += 1
                UserDefaults.standard.set(self.seconds, forKey: "savedSeconds")
                
                var dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
                dailyRecords[currentDay] = self.seconds
                UserDefaults.standard.set(dailyRecords, forKey: "dailyRecords")
            }
            self.updateStatusItemUI()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func toggleTimer() {
        isRunning.toggle()
        
        let soundName = isRunning ? "Ping" : "Pop" 
        if let sound = NSSound(named: soundName) {
            sound.volume = 1.0 // 소리 최대로 설정
            sound.play()
        }
        
        updateStatusItemUI()
    }
    
    func getRemainingTimeToMidnight() -> String {
        let now = Date()
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { 
            return "00:00:00" 
        }
        let timeInterval = tomorrow.timeIntervalSince(now) + Double(midnightOffset)
        let totalSeconds = Int(timeInterval)
        
        let sign = totalSeconds < 0 ? "-" : ""
        let absSeconds = abs(totalSeconds)
        
        let h = absSeconds / 3600
        let m = (absSeconds % 3600) / 60
        let s = absSeconds % 60
        
        return String(format: "%@%02d:%02d:%02d", sign, h, m, s)
    }
    
    func updateStatusItemUI() {
        if let button = statusItem.button {
            let timeString = formatTime(seconds)
            let remainingString = getRemainingTimeToMidnight()
            
            let fullString = "\(timeString) | 🌙 \(remainingString)"
            
            let attributedTitle = NSMutableAttributedString(string: fullString, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            ])
            
            let color = isRunning ? NSColor.systemRed : NSColor.systemGray
            let timeRange = (fullString as NSString).range(of: timeString)
            if timeRange.location != NSNotFound {
                attributedTitle.addAttribute(.foregroundColor, value: color, range: timeRange)
            }
            
            let remainingRange = (fullString as NSString).range(of: " | 🌙 \(remainingString)")
            if remainingRange.location != NSNotFound {
                attributedTitle.addAttribute(.foregroundColor, value: NSColor.labelColor, range: remainingRange)
            }
            
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
