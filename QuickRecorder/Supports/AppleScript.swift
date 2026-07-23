//
//  AppleScript.swift
//  QuickRecorder
//
//  Created by apple on 2024/9/23.
//

import Foundation
import AppKit
import ScreenCaptureKit

private func redispatchToMainIfNeeded(_ command: NSScriptCommand) -> Bool {
    guard !Thread.isMainThread else { return false }
    DispatchQueue.main.async {
        _ = command.performDefaultImplementation()
    }
    return true
}

class selectScreen: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if redispatchToMainIfNeeded(self) { return nil }
        if SCContext.stream != nil {
            createAlert(title: "Error".local, message: "Already recording!".local, button1: "OK".local).runModal()
            return nil
        }
        let arguments = evaluatedArguments ?? [:]
        SCContext.updateAvailableContent {
            DispatchQueue.main.async {
                closeAllWindow()
                if var index = arguments["index"] as? Int {
                    guard let screens = SCContext.availableContent?.displays else { return }
                    index -= 1
                    closeAllWindow()
                    if index >= screens.count || index < 0 {
                        createAlert(title: "Error".local, message: "Invalid screen number!".local, button1: "OK".local).runModal()
                        return
                    } else {
                        let screen = screens[index]
                        AppDelegate.shared.createCountdownPanel(screen: screen) {
                            AppDelegate.shared.prepRecord(type: "display", screens: screen, windows: nil)
                        }
                    }
                } else {
                    closeAllWindow()
                    AppDelegate.shared.createNewWindow(view: ScreenSelector(), title: "Screen Selector".local)
                }
            }
        }
        return nil
    }
}

class selectArea: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if redispatchToMainIfNeeded(self) { return nil }
        if SCContext.stream != nil {
            createAlert(title: "Error".local, message: "Already recording!".local, button1: "OK".local).runModal()
            return nil
        }
        SCContext.updateAvailableContent {
            DispatchQueue.main.async {
                closeAllWindow()
                DispatchQueue.main.async {
                    AppDelegate.shared.showAreaSelector(size: NSSize(width: 600, height: 450))
                    var currentDisplay = SCContext.getSCDisplayWithMouse()
                    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .rightMouseDown, .leftMouseDown, .otherMouseDown]) { event in
                        let display = SCContext.getSCDisplayWithMouse()
                        if display != currentDisplay {
                            currentDisplay = display
                            closeAllWindow()
                            AppDelegate.shared.showAreaSelector(size: NSSize(width: 600, height: 450))
                        }
                    }
                }
            }
        }
        return nil
    }
}

class selectWindows: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if redispatchToMainIfNeeded(self) { return nil }
        if SCContext.stream != nil {
            createAlert(title: "Error".local, message: "Already recording!".local, button1: "OK".local).runModal()
            return nil
        }
        let arguments = evaluatedArguments ?? [:]
        SCContext.updateAvailableContent {
            DispatchQueue.main.async {
                closeAllWindow()
                if let title = arguments["title"] as? String {
                    var windows = [SCWindow]()
                    guard let w = SCContext.availableContent?.windows.filter({ $0.title == title }) else { return }
                    windows = w
                    if let app = arguments["app"] as? String {
                        guard let w = SCContext.availableContent?.windows.filter({ $0.title == title && $0.owningApplication?.applicationName == app }) else { return }
                        windows = w
                    }
                    closeAllWindow()
                    if windows.isEmpty {
                        createAlert(title: "Error".local, message: "No such window!".local, button1: "OK".local).runModal()
                        return
                    }
                    if windows.count > 1 {
                        AppDelegate.shared.createNewWindow(view: WinSelector(), title: "Window Selector".local)
                        createAlert(title: "Error".local, message: "Duplicate window exists, please select it manually!".local, button1: "OK".local).runModal()
                        return
                    }
                    guard let window = windows.first else { return }
                    guard let screens = SCContext.availableContent?.displays else { return }
                    var s = [SCDisplay]()
                    for screen in screens {
                        if NSIntersectsRect(screen.frame, window.frame) { if !s.contains(screen) { s.append(screen) }}
                    }
                    if s.isEmpty {
                        createAlert(title: "Error".local, message: "Unable to find the screen this window belongs to!".local, button1: "OK".local).runModal()
                        return
                    }
                    guard let firstDisplay = s.first else { return }
                    let targetDisplay = SCContext.getSCDisplayWithMouse()
                        .flatMap { s.contains($0) ? $0 : nil }
                        ?? firstDisplay
                    AppDelegate.shared.createCountdownPanel(screen: targetDisplay) {
                        AppDelegate.shared.prepRecord(
                            type: "window",
                            screens: targetDisplay,
                            windows: [window]
                        )
                    }
                } else {
                    closeAllWindow()
                    AppDelegate.shared.createNewWindow(view: WinSelector(), title: "Window Selector".local)
                }
            }
        }
        return nil
    }
}

class recordAudio: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if redispatchToMainIfNeeded(self) { return nil }
        if SCContext.stream != nil {
            createAlert(title: "Error".local, message: "Already recording!".local, button1: "OK".local).runModal()
            return nil
        }
        guard let displayID = SCContext.getScreenWithMouse()?.displayID else { return nil }
        let microphoneOverride = evaluatedArguments?["mic"] as? Bool
        closeAllWindow()
        AppDelegate.shared.prepRecord(
            type: "audio",
            displayID: displayID,
            windowIDs: nil,
            recordMicrophoneOverride: microphoneOverride
        )
        return nil
    }
}

class setPreferences: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if redispatchToMainIfNeeded(self) { return nil }
        if SCContext.stream != nil {
            createAlert(title: "Error".local, message: "Already recording!".local, button1: "OK".local).runModal()
            return nil
        }
        let arguments = evaluatedArguments ?? [:]
        if let hires = arguments["hires"] as? Bool { UserDefaults.standard.set(hires, forKey: "highRes") }
        if let fps = arguments["fps"] as? Int { UserDefaults.standard.set(fps, forKey: "frameRate") }
        if let cursor = arguments["cursor"] as? Bool { UserDefaults.standard.set(cursor, forKey: "showMouse") }
        if let sound = arguments["sound"] as? Bool { UserDefaults.standard.set(sound, forKey: "recordWinSound") }
        if let microphone = arguments["microphone"] as? Bool { UserDefaults.standard.set(microphone, forKey: "recordMic") }
        if let quality = arguments["quality"] as? Int {
            if [1,2,3].contains(quality) {
                switch quality {
                    case 1: UserDefaults.standard.set(0.3, forKey: "videoQuality")
                    case 2: UserDefaults.standard.set(0.7, forKey: "videoQuality")
                    default: UserDefaults.standard.set(1.0, forKey: "videoQuality")
                }
            }
        }
        if let micname = arguments["micname"] as? String {
            if let microphoneID = SCContext.microphoneID(for: micname) {
                UserDefaults.standard.set(microphoneID, forKey: "micDevice")
            }
        }
        if let hdr = arguments["hdr"] as? Bool {
            if #available(macOS 15.0, *) {
                UserDefaults.standard.set(hdr, forKey: "recordHDR")
            }
        }
        return nil
    }
}
