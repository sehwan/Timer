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
        setupNotifications()
    }
    
    func setupNotifications() {
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(self, selector: #selector(stopTimer), name: NSWorkspace.willSleepNotification, object: nil)
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(stopTimer),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
    }

    @objc func stopTimer() {
        if isRunning {
            isRunning = false
            updateStatusItemUI()
        }
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
        menu.addItem(NSMenuItem(title: "하루의 마무리 시간 설정", action: #selector(editFinishTime), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "오늘 기록 수정", action: #selector(editTodayRecord), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "어제 기록 수정", action: #selector(editYesterdayRecord), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        if let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)),
           let daysPassed = calendar.dateComponents([.day], from: calendar.startOfDay(for: yearStart), to: calendar.startOfDay(for: now)).day,
           let daysRemaining = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: yearEnd).day {
            let yearEndItem = NSMenuItem(title: "📅 \(daysPassed) / \(daysRemaining)", action: nil, keyEquivalent: "")
            yearEndItem.isEnabled = false
            menu.addItem(yearEndItem)
        }
        
        var totalSeconds = 0
        let dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
        let logicalNow = Date().addingTimeInterval(-Double(midnightOffset))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        for i in (1...7).reversed() {
            if let pastDate = Calendar.current.date(byAdding: .day, value: -i, to: logicalNow) {
                let dateString = formatter.string(from: pastDate)
                totalSeconds += dailyRecords[dateString] ?? 0
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        let avgSeconds = totalSeconds / 7
        let avgItem = NSMenuItem(title: "📊 \(formatTime(avgSeconds))", action: nil, keyEquivalent: "")
        avgItem.isEnabled = false
        menu.addItem(avgItem)
        
        for i in (1...7).reversed() {
            if let pastDate = Calendar.current.date(byAdding: .day, value: -i, to: logicalNow) {
                let dateString = formatter.string(from: pastDate)
                let secs = dailyRecords[dateString] ?? 0
                let timeStr = formatTime(secs)
                let dayLabel = i == 1 ? "day" : "days"
                let item = NSMenuItem(title: "\(i) \(dayLabel) ago: \(timeStr)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }
    
    @objc func editFinishTime() {
        let currentH = midnightOffset / 3600
        let currentM = (midnightOffset % 3600) / 60
        let defaultVal = String(format: "%02d:%02d", currentH, currentM)
        
        showInputAlert(title: "하루의 마무리 시간 설정", message: "예시: 02:00 (새벽 2시)", defaultValue: defaultVal) { input in
            guard let input = input else { return }
            let parts = input.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }.compactMap { Int($0) }
            if parts.count >= 1 {
                let h = parts[0]
                let m = parts.count >= 2 ? parts[1] : 0
                self.midnightOffset = h * 3600 + m * 60
                UserDefaults.standard.set(self.midnightOffset, forKey: "midnightOffset")
                self.updateStatusItemUI()
            }
        }
    }
    
    @objc func editTodayRecord() {
        let defaultVal = formatSecondsToTime(seconds)
        showInputAlert(title: "오늘 기록 수정", message: "형식: HH:mm:ss", defaultValue: defaultVal) { input in
            guard let input = input, let newSeconds = self.parseTimeToSeconds(input) else { return }
            self.seconds = newSeconds
            UserDefaults.standard.set(self.seconds, forKey: "savedSeconds")
            
            let currentDay = self.currentDateString()
            var dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
            dailyRecords[currentDay] = self.seconds
            UserDefaults.standard.set(dailyRecords, forKey: "dailyRecords")
            
            self.updateStatusItemUI()
        }
    }
    
    @objc func editYesterdayRecord() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let logicalNow = Date().addingTimeInterval(-Double(midnightOffset))
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: logicalNow) else { return }
        let dateString = formatter.string(from: yesterday)
        
        var dailyRecords = UserDefaults.standard.dictionary(forKey: "dailyRecords") as? [String: Int] ?? [:]
        let currentVal = dailyRecords[dateString] ?? 0
        let defaultVal = formatSecondsToTime(currentVal)
        
        showInputAlert(title: "어제 기록 수정 (\(dateString))", message: "형식: HH:mm:ss", defaultValue: defaultVal) { input in
            guard let input = input, let newSeconds = self.parseTimeToSeconds(input) else { return }
            dailyRecords[dateString] = newSeconds
            UserDefaults.standard.set(dailyRecords, forKey: "dailyRecords")
            self.updateStatusItemUI()
        }
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

    func showInputAlert(title: String, message: String, defaultValue: String, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = defaultValue
        alert.accessoryView = inputTextField
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion(inputTextField.stringValue)
        } else {
            completion(nil)
        }
    }
    
    func parseTimeToSeconds(_ timeStr: String) -> Int? {
        let parts = timeStr.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }.compactMap { Int($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        } else if parts.count == 2 {
            return parts[0] * 3600 + parts[1] * 60
        } else if parts.count == 1 {
            return parts[0] * 60
        }
        return nil
    }

    func formatSecondsToTime(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
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
