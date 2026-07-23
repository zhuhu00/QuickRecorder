//
//  SCContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import AVFAudio
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UserNotifications
import SwiftLAME
import SwiftUI
import AECAudioStream

struct WriterSessionGate {
    private(set) var sourceTime: CMTime?

    var isOpen: Bool { sourceTime != nil }

    mutating func open(at sourceTime: CMTime) -> Bool {
        guard self.sourceTime == nil,
              sourceTime.flags.contains(.valid) else { return false }
        self.sourceTime = sourceTime
        return true
    }

    mutating func close() {
        sourceTime = nil
    }

    func accepts(_ presentationTime: CMTime) -> Bool {
        guard let sourceTime,
              presentationTime.flags.contains(.valid) else { return false }
        return CMTimeCompare(presentationTime, sourceTime) >= 0
    }
}

@MainActor
private final class LegacyAssetExportJob {
    private let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously { [self] in
                Task { @MainActor in
                    switch session.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: session.error ?? NSError(
                            domain: "ExportError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Export failed for an unknown reason."]
                        ))
                    case .cancelled:
                        continuation.resume(throwing: NSError(
                            domain: "ExportCancelled",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Export was cancelled."]
                        ))
                    default:
                        continuation.resume(throwing: NSError(
                            domain: "ExportError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Export finished in an unexpected state."]
                        ))
                    }
                }
            }
        }
    }
}

class SCContext {
    static var trimingList = [URL]()
    static var firstFrame: CMSampleBuffer?
    static var autoStop = 0
    static var recordCam = ""
    static var captureSession: AVCaptureSession!
    static var frameCache: CMSampleBuffer?
    static var filter: SCContentFilter?
    static var isMagnifierEnabled = false
    static var saveFrame = false
    static var isPaused = false
    static var isSkipFrame = false
    static var lastPTS: CMTime?
    private static let recordingTimelineLock = NSLock()
    private static var activePauseStartedAt: CMTime?
    private static var completedPauseRanges = [CMTimeRange]()
    private static let writerSessionLock = NSLock()
    private static var writerSessionGate = WriterSessionGate()
    static var screenArea: NSRect?
    static let audioEngine = AVAudioEngine()
    static let AECEngine = AECAudioStream(sampleRate: 48000)
    static var backgroundColor: CGColor = CGColor.black
    static var filePath: String!
    static var filePath1: String!
    static var filePath2: String!
    static var audioFile: AVAudioFile?
    static var audioFile2: AVAudioFile?
    static var vW: AVAssetWriter!
    static var vwInput, awInput, micInput: AVAssetWriterInput!
    static var startTime: Date?
    static var timePassed: TimeInterval = 0
    static var stream: SCStream!
    static var screen: SCDisplay?
    static var window: [SCWindow]?
    static var streamType: StreamType?
    enum MicrophoneCaptureMode {
        case none
        case defaultInput
        case defaultInputWithAEC
        case selectedDevice
    }
    private static let microphoneCaptureLock = NSLock()
    private static var microphoneCaptureMode = MicrophoneCaptureMode.none
    static let streamOutputQueue = DispatchQueue(
        label: "io.github.zhuhu00.QuickRecorder.stream-output",
        qos: .userInitiated
    )
    private static let lifecycleLock = NSLock()
    private static var recordingLifecycle = RecordingLifecycle()
    static var isStartingCapture: Bool { lifecyclePhase == .starting }
    static var isStopping: Bool { lifecyclePhase == .stopping }
    private static var stopCompletions = [() -> Void]()
    private static let availableContentLock = NSLock()
    private static var availableContentStorage: SCShareableContent?
    static var availableContent: SCShareableContent? {
        get {
            availableContentLock.lock()
            defer { availableContentLock.unlock() }
            return availableContentStorage
        }
        set {
            availableContentLock.lock()
            availableContentStorage = newValue
            availableContentLock.unlock()
        }
    }
    static let excludedApps = ["", "com.apple.dock", "com.apple.screencaptureui", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status"]

    private static var lifecyclePhase: RecordingLifecycle.Phase {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return recordingLifecycle.phase
    }

    static func beginRecordingStart() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return recordingLifecycle.beginStart()
    }

    @discardableResult
    static func completeRecordingStart() -> Bool {
        lifecycleLock.lock()
        let completed = recordingLifecycle.completeStart()
        lifecycleLock.unlock()
        return completed
    }

    static func failRecordingStart() {
        lifecycleLock.lock()
        recordingLifecycle.fail()
        lifecycleLock.unlock()
    }

    private static func updateLifecyclePaused(_ paused: Bool) {
        lifecycleLock.lock()
        _ = recordingLifecycle.setPaused(paused)
        lifecycleLock.unlock()
    }

    private static func registerRecordingStop(
        completion: (() -> Void)?
    ) -> RecordingLifecycle.StopRequest {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let request = recordingLifecycle.requestStop()
        if request != .inactive, let completion {
            stopCompletions.append(completion)
        }
        return request
    }

    private static func finishRecordingLifecycle() -> [() -> Void] {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        recordingLifecycle.finish()
        let completions = stopCompletions
        stopCompletions.removeAll()
        return completions
    }

    static func completeRecordingStartCancellation() {
        let completions = finishRecordingLifecycle()
        completions.forEach { $0() }
    }
    
    static func updateAvailableContent(completion: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                updateAvailableContent(completion: completion)
            }
            return
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            requestPermissions()
            return
        }

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            DispatchQueue.main.async {
                if let error {
                    switch error {
                    case SCStreamError.userDeclined:
                        requestPermissions()
                    default:
                        print("Error: failed to fetch available content: ".local, error.localizedDescription)
                    }
                    return
                }

                guard let content, !content.displays.isEmpty else {
                    print("There needs to be at least one display connected!".local)
                    return
                }
                availableContent = content
                completion()
            }
        }
    }
    
    static func getSelf() -> SCRunningApplication? {
        return availableContent?.applications.first(where: {
            Bundle.main.bundleIdentifier == $0.bundleIdentifier
        })
    }
    
    static func getSelfWindows() -> [SCWindow]? {
        return availableContent?.windows.filter( {
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            && title != "Mouse Pointer".local
            && title != "Screen Magnifier".local
            && title != "Camera Overlayer".local
        })
    }
    
    static func getWindows(isOnScreen: Bool = true, hideSelf: Bool = true) -> [SCWindow] {
        guard let availableContent else { return [] }
        var windows = availableContent.windows.filter {
            guard let app =  $0.owningApplication,
                  let title = $0.title else {//, !title.isEmpty else {
                return false
            }
            return !excludedApps.contains(app.bundleIdentifier)
            && !title.contains("Item-0")
            && title != "Window"
            && $0.frame.width > 40
            && $0.frame.height > 40
        }
        if isOnScreen { windows = windows.filter({$0.isOnScreen == true}) }
        if hideSelf && ud.bool(forKey: "hideSelf") { windows = windows.filter({$0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier}) }
        return windows
    }
    
    static func getAppIcon(_ app: SCRunningApplication) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 69, height: 69)
            return icon
        }
        let icon = NSImage(
            systemSymbolName: "questionmark.app.dashed",
            accessibilityDescription: "blank icon"
        ) ?? NSImage(size: NSSize(width: 69, height: 69))
        icon.size = NSSize(width: 69, height: 69)
        return icon
    }
    
    static func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
        return screenWithMouse
    }
    
    static func getSCDisplayWithMouse() -> SCDisplay? {
        if let displays = availableContent?.displays {
            for display in displays {
                if let currentDisplayID = getScreenWithMouse()?.displayID {
                    if display.displayID == currentDisplayID {
                        return display
                    }
                }
            }
        }
        return nil
    }
    
    static func getFilePath(capture: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        return ud.string(forKey: "saveDirectory")! + (capture ? "/Capturing at ".local : "/Recording at ".local) + dateFormatter.string(from: Date())
    }
    
    static func updateAudioSettings(format: String = ud.string(forKey: "audioFormat") ?? "", rate: Int = 48000) -> [String : Any] {
        var audioSettings: [String : Any] = [AVSampleRateKey : rate, AVNumberOfChannelsKey : 2] // reset audioSettings
        var bitRate = ud.integer(forKey: "audioQuality") * 1000
        if rate < 44100 { bitRate = min(64000, bitRate / 2) }
        switch format {
        case AudioFormat.mp3.rawValue: fallthrough
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = bitRate
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = ud.string(forKey: "videoFormat") != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =  bitRate
        default:
            assertionFailure("unknown audio format while setting audio settings: ".local + (ud.string(forKey: "audioFormat") ?? "[no defaults]".local))
        }
        return audioSettings
    }
    
    static func getBackgroundColor() -> CGColor {
        guard let color = ud.string(forKey: "background") else { return CGColor.black  }
        if color == BackgroundType.wallpaper.rawValue { return CGColor.black }
        switch color {
            case "clear": backgroundColor = CGColor.clear
            case "black": backgroundColor = CGColor.black
            case "white": backgroundColor = CGColor.white
            case "gray": backgroundColor = NSColor.systemGray.cgColor
            case "yellow": backgroundColor = NSColor.systemYellow.cgColor
            case "orange": backgroundColor = NSColor.systemOrange.cgColor
            case "green": backgroundColor = NSColor.systemGreen.cgColor
            case "blue": backgroundColor = NSColor.systemBlue.cgColor
            case "red": backgroundColor = NSColor.systemRed.cgColor
            default: backgroundColor = ud.cgColor(forKey: "userColor") ?? CGColor.black
        }
        return backgroundColor
    }
    
    static func performMicCheck() async {
        guard ud.bool(forKey: "recordMic") == true else { return }
        if await AVCaptureDevice.requestAccess(for: .audio) { return }

        ud.setValue(false, forKey: "recordMic")
        DispatchQueue.main.async {
            let alert = createAlert(title: "Permission Required",
                                                       message: "QuickRecorder needs permission to record your microphone.",
                                                       button1: "Open Settings",
                                                       button2: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
    
    private static func requestPermissions() {
        DispatchQueue.main.async {
            let alert = createAlert(title: "Permission Required",
                                                       message: "QuickRecorder needs screen recording permissions, even if you only intend on recording audio.",
                                                       button1: "Open Settings",
                                                       button2: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
    }
    
    static func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized, .restricted, .notDetermined:
            break
        case .denied:
            DispatchQueue.main.async {
                let alert = createAlert(title: "Permission Required",
                                                           message: "QuickRecorder needs this permission to record your camera.",
                                                           button1: "Open Settings",
                                                           button2: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        @unknown default:
            break
        }
    }
    
    static func getWallpaper(_ display: SCDisplay) -> NSImage? {
        guard let screen = display.nsScreen else { return nil }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        do {
            var wallpaper: NSImage?
            try wallpaper = NSImage(data: Data(contentsOf: url))
            if let w = wallpaper { return w }
        } catch {
            print("load wallpaper error: \(error)")
        }
        return nil
    }
    
    static func getRecordingSize() -> String {
        do {
            let fileAttr = try fd.attributesOfItem(atPath: filePath)
            let byteFormat = ByteCountFormatter()
            byteFormat.allowedUnits = [.useMB]
            byteFormat.countStyle = .file
            return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
        } catch {
            print(String(format: "failed to fetch file for size indicator: %@".local, error.localizedDescription))
        }
        return "Unknown".local
    }
    
    static func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        if recordingIsPaused() { return formatter.string(from: timePassed) ?? "Unknown".local }
        timePassed = Date.now.timeIntervalSince(startTime ?? Date.now)
        return formatter.string(from: timePassed) ?? "Unknown".local
    }
    
    static func isCameraRunning() -> Bool {
        return captureSession?.isRunning ?? false
    }

    static func resetRecordingTimeline() {
        recordingTimelineLock.lock()
        isPaused = false
        activePauseStartedAt = nil
        completedPauseRanges.removeAll()
        recordingTimelineLock.unlock()
    }

    static func recordingIsPaused() -> Bool {
        recordingTimelineLock.lock()
        let paused = isPaused
        recordingTimelineLock.unlock()
        return paused
    }
    
    static func pauseRecording() {
        guard !isStopping else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let elapsed = Date.now.timeIntervalSince(startTime ?? Date.now)

        recordingTimelineLock.lock()
        if isPaused {
            if let pauseStart = activePauseStartedAt,
               CMTimeCompare(now, pauseStart) > 0 {
                let pauseRange = CMTimeRange(start: pauseStart, end: now)
                completedPauseRanges.append(pauseRange)
            }
            activePauseStartedAt = nil
            isPaused = false
        } else {
            activePauseStartedAt = now
            isPaused = true
        }
        let paused = isPaused
        recordingTimelineLock.unlock()

        updateLifecyclePaused(paused)
        PopoverState.shared.isPaused = paused
        if paused {
            timePassed = elapsed
        } else {
            startTime = Date.now.addingTimeInterval(-1) - SCContext.timePassed
        }
    }

    static func sampleBufferForRecording(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        recordingTimelineLock.lock()
        let activePauseStart = activePauseStartedAt
        let pauseRanges = completedPauseRanges
        recordingTimelineLock.unlock()

        guard presentationTime.flags.contains(.valid) else {
            return activePauseStart == nil ? sampleBuffer : nil
        }
        if let activePauseStart,
           CMTimeCompare(presentationTime, activePauseStart) >= 0 {
            return nil
        }

        var offset = CMTime.zero
        for pauseRange in pauseRanges {
            let pauseEnd = CMTimeRangeGetEnd(pauseRange)
            if CMTimeCompare(presentationTime, pauseRange.start) >= 0,
               CMTimeCompare(presentationTime, pauseEnd) < 0 {
                return nil
            }
            if CMTimeCompare(presentationTime, pauseEnd) >= 0 {
                offset = CMTimeAdd(offset, pauseRange.duration)
            }
        }

        guard CMTimeCompare(offset, .zero) > 0 else { return sampleBuffer }
        return adjustTime(sample: sampleBuffer, by: offset)
    }

    static func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        guard let adjustedSample = sampleBufferForRecording(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(adjustedSample)

        writerSessionLock.lock()
        defer { writerSessionLock.unlock() }
        guard writerSessionGate.accepts(presentationTime),
              let writer = vW,
              writer.status == .writing,
              let microphoneInput = micInput,
              microphoneInput.isReadyForMoreMediaData else { return }
        if !microphoneInput.append(adjustedSample) {
            let error = writer.error?.localizedDescription ?? "Unknown Error".local
            print("Failed to append microphone sample: \(error)")
        }
    }

    static func startWriterSessionIfNeeded(at sourceTime: CMTime) -> Bool {
        writerSessionLock.lock()
        defer { writerSessionLock.unlock() }

        if writerSessionGate.isOpen { return true }
        guard sourceTime.flags.contains(.valid),
              let writer = vW,
              writer.status == .writing else { return false }
        writer.startSession(atSourceTime: sourceTime)
        return writerSessionGate.open(at: sourceTime)
    }

    static func resetWriterSession() {
        writerSessionLock.lock()
        writerSessionGate.close()
        writerSessionLock.unlock()
    }

    static func setMicrophoneCaptureMode(_ mode: MicrophoneCaptureMode) {
        microphoneCaptureLock.lock()
        microphoneCaptureMode = mode
        microphoneCaptureLock.unlock()
    }

    static func isCapturingSelectedMicrophone() -> Bool {
        microphoneCaptureLock.lock()
        let isSelectedDevice = microphoneCaptureMode == .selectedDevice
        microphoneCaptureLock.unlock()
        return isSelectedDevice
    }

    static func stopMicrophoneCapture() {
        microphoneCaptureLock.lock()
        let mode = microphoneCaptureMode
        microphoneCaptureMode = .none
        microphoneCaptureLock.unlock()

        switch mode {
        case .defaultInputWithAEC:
            try? AECEngine.stopAudioUnit()
        case .defaultInput:
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        case .selectedDevice:
            AudioRecorder.shared.stopAndDrain()
        case .none:
            break
        }
    }

    private static func finishSystemAudioRecording(
        outputPath: String,
        systemAudioPath: String,
        audioFormat: String,
        recordedMicrophone: Bool,
        shouldRemuxAudio: Bool,
        shouldShowPreview: Bool,
        completion: @escaping () -> Void
    ) {
        if audioFormat == AudioFormat.mp3.rawValue && !recordedMicrophone {
            Task {
                let outputURL = (String(outputPath.dropLast(4)) + ".mp3").url
                do {
                    try await m4a2mp3(inputUrl: systemAudioPath.url, outputUrl: outputURL)
                    try? fd.removeItem(atPath: systemAudioPath)
                    if !shouldShowPreview {
                        let title = "Recording Completed".local
                        let body = String(format: "File saved to: %@".local, outputURL.path.removingPercentEncoding!)
                        let id = "quickrecorder.completed.\(UUID().uuidString)"
                        showNotification(title: title, body: body, id: id)
                        completion()
                    } else {
                        DispatchQueue.main.async {
                            showPreview(path: outputURL.path, image: NSImage(named: "audioIcon"))
                            completion()
                        }
                    }
                } catch {
                    showNotification(title: "Failed to save file".local, body: "\(error.localizedDescription)", id: "quickrecorder.error.\(UUID().uuidString)")
                    completion()
                }
            }
            return
        }

        if shouldRemuxAudio && recordedMicrophone {
            let packageURL = outputPath.url
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let document = try qmaPackageHandle.load(from: packageURL)
                    DispatchQueue.main.async {
                        let audioPlayerManager = AudioPlayerManager()
                        audioPlayerManager.loadAudioFiles(
                            format: document.info.format,
                            package: packageURL,
                            encoder: document.info.encoder,
                            saveMP3: document.info.exportMP3
                        )
                        audioPlayerManager.sysVol = document.info.sysVol
                        audioPlayerManager.micVol = document.info.micVol
                        let exportMP3 = document.info.exportMP3
                        let format = exportMP3 ? "mp3" : document.info.format
                        let saveURL = packageURL.deletingPathExtension().appendingPathExtension(format)
                        audioPlayerManager.saveFile(
                            saveURL,
                            saveAsMP3: exportMP3,
                            deleteQMAAfterExport: true,
                            completion: completion
                        )
                    }
                } catch {
                    showNotification(title: "Failed to save file".local, body: "\(error.localizedDescription)", id: "quickrecorder.error.\(UUID().uuidString)")
                    completion()
                }
            }
            return
        }

        if !shouldShowPreview {
            let title = "Recording Completed".local
            let body = String(format: "File saved to: %@".local, outputPath)
            let id = "quickrecorder.completed.\(UUID().uuidString)"
            showNotification(title: title, body: body, id: id)
            completion()
        } else {
            DispatchQueue.main.async {
                showPreview(path: outputPath, image: NSImage(named: "qmaIcon"))
                completion()
            }
        }
    }

    private static func reportMicrophoneWriterFailure(_ writer: AVAssetWriter?) {
        let error = writer?.error?.localizedDescription ?? "Unknown Error".local
        print("Microphone writing failed with status: \(String(describing: writer?.status)), error: \(error)")
        showNotification(title: "Failed to save file".local, body: error, id: "quickrecorder.error.\(UUID().uuidString)")
    }

    private struct RecordingStopContext {
        let stream: SCStream?
        let streamType: StreamType
        let writer: AVAssetWriter?
        let videoInput: AVAssetWriterInput?
        let systemAudioInput: AVAssetWriterInput?
        let microphoneInput: AVAssetWriterInput?
        let outputPath: String?
        let systemAudioPath: String?
        let recordedMicrophone: Bool
        let recordWindowSound: Bool
        let shouldRemuxAudio: Bool
        let shouldShowPreview: Bool
        let shouldTrimVideo: Bool
        let audioFormat: String
        let videoFormat: String
    }

    static func stopRecording(streamError: Error? = nil, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                stopRecording(streamError: streamError, completion: completion)
            }
            return
        }

        guard let stoppedStreamType = streamType else {
            completion?()
            return
        }
        switch registerRecordingStop(completion: completion) {
        case .cancelStart:
            return
        case .start:
            break
        case .join:
            if let streamError {
                print("Stream stopped while recording was already finalizing: \(streamError.localizedDescription)")
            }
            return
        case .inactive:
            print("Ignoring stop request because the recording lifecycle is not active.")
            completion?()
            return
        }

        autoStop = 0
        if ud.bool(forKey: "preventSleep") { SleepPreventer.shared.allowSleep() }
        AppDelegate.shared.stopGlobalMouseMonitor()
        updateStatusBar()

        let context = RecordingStopContext(
            stream: stream,
            streamType: stoppedStreamType,
            writer: vW,
            videoInput: vwInput,
            systemAudioInput: awInput,
            microphoneInput: micInput,
            outputPath: filePath,
            systemAudioPath: filePath1,
            recordedMicrophone: micInput != nil,
            recordWindowSound: ud.bool(forKey: "recordWinSound"),
            shouldRemuxAudio: ud.bool(forKey: "remuxAudio"),
            shouldShowPreview: ud.bool(forKey: "showPreview"),
            shouldTrimVideo: ud.bool(forKey: "trimAfterRecord"),
            audioFormat: ud.string(forKey: "audioFormat") ?? AudioFormat.aac.rawValue,
            videoFormat: ud.string(forKey: "videoFormat") ?? VideoFormat.mp4.rawValue
        )

        let drainStreamOutput: (Error?) -> Void = { stopError in
            streamOutputQueue.async {
                finalizeCapture(context, streamError: stopError)
            }
        }

        if let streamError {
            drainStreamOutput(streamError)
        } else if let activeStream = context.stream {
            activeStream.stopCapture { stopError in
                drainStreamOutput(stopError)
            }
        } else {
            drainStreamOutput(nil)
        }
    }

    private static func finalizeCapture(_ context: RecordingStopContext, streamError: Error?) {
        if let streamError {
            print("Screen capture stopped with error: \(streamError.localizedDescription)")
        }

        resetWriterSession()
        if context.recordedMicrophone {
            stopMicrophoneCapture()
            context.microphoneInput?.markAsFinished()
        }

        audioFile = nil
        audioFile2 = nil
        cleanupCaptureUI()

        if context.streamType == .systemaudio {
            finalizeSystemAudioRecording(context)
        } else {
            finalizeVideoRecording(context)
        }
    }

    private static func cleanupCaptureUI() {
        DispatchQueue.main.async {
            recordCam = ""
            isMagnifierEnabled = false
            mousePointer.orderOut(nil)
            screenMagnifier.orderOut(nil)
            if let window = NSApp.windows.first(where: { $0.title == "Area Overlayer".local }) {
                window.close()
            }
            AppDelegate.shared.closeCamera()
        }
    }

    private static func finalizeSystemAudioRecording(_ context: RecordingStopContext) {
        guard let outputPath = context.outputPath,
              let systemAudioPath = context.systemAudioPath else {
            showNotification(title: "Failed to save file".local, body: "Unknown Error".local, id: "quickrecorder.error.\(UUID().uuidString)")
            completeRecordingLifecycle()
            return
        }

        let processOutput = {
            finishSystemAudioRecording(
                outputPath: outputPath,
                systemAudioPath: systemAudioPath,
                audioFormat: context.audioFormat,
                recordedMicrophone: context.recordedMicrophone,
                shouldRemuxAudio: context.shouldRemuxAudio,
                shouldShowPreview: context.shouldShowPreview,
                completion: completeRecordingLifecycle
            )
        }

        guard context.recordedMicrophone else {
            processOutput()
            return
        }
        guard let writer = context.writer else {
            reportMicrophoneWriterFailure(nil)
            completeRecordingLifecycle()
            return
        }

        writer.finishWriting {
            guard writer.status == .completed else {
                reportMicrophoneWriterFailure(writer)
                completeRecordingLifecycle()
                return
            }
            processOutput()
        }
    }

    private static func finalizeVideoRecording(_ context: RecordingStopContext) {
        context.videoInput?.markAsFinished()
        context.systemAudioInput?.markAsFinished()

        guard let writer = context.writer,
              let outputPath = context.outputPath else {
            showNotification(title: "Failed to save file".local, body: "Unknown Error".local, id: "quickrecorder.error.\(UUID().uuidString)")
            completeRecordingLifecycle()
            return
        }

        writer.finishWriting {
            guard writer.status == .completed else {
                let error = writer.error?.localizedDescription ?? "Unknown Error".local
                print("Video writing failed with status: \(writer.status), error: \(error)")
                showNotification(title: "Failed to save file".local, body: error, id: "quickrecorder.error.\(UUID().uuidString)")
                completeRecordingLifecycle()
                return
            }

            let outputURL = outputPath.url
            if context.recordedMicrophone && context.recordWindowSound && context.shouldRemuxAudio {
                mixAudioTracks(videoURL: outputURL, videoFormat: context.videoFormat) { result in
                    switch result {
                    case .success(let url):
                        print("Exported video to \(url.path)")
                        presentVideoOutput(url, context: context)
                    case .failure(let error):
                        print("Failed to export video: \(error.localizedDescription)")
                        showNotification(title: "Failed to save file".local, body: error.localizedDescription, id: "quickrecorder.error.\(UUID().uuidString)")
                        completeRecordingLifecycle()
                    }
                }
            } else {
                presentVideoOutput(outputURL, context: context)
            }
        }
    }

    private static func presentVideoOutput(_ outputURL: URL, context: RecordingStopContext) {
        DispatchQueue.main.async {
            if !context.shouldShowPreview {
                showNotification(
                    title: "Recording Completed".local,
                    body: String(format: "File saved to: %@".local, outputURL.path),
                    id: "quickrecorder.completed.\(UUID().uuidString)"
                )
            }
            if context.shouldTrimVideo {
                AppDelegate.shared.createNewWindow(
                    view: VideoTrimmerView(videoURL: outputURL),
                    title: outputURL.lastPathComponent,
                    only: false
                )
            } else if context.shouldShowPreview {
                showPreview(path: outputURL.path)
            }
            completeRecordingLifecycle()
        }
    }

    private static func completeRecordingLifecycle() {
        DispatchQueue.main.async {
            resetWriterSession()
            resetRecordingTimeline()
            PopoverState.shared.isPaused = false
            hideMousePointer = false
            hideScreenMagnifier = false
            lastPTS = nil
            window = nil
            screen = nil
            startTime = nil
            stream = nil
            streamType = nil
            firstFrame = nil
            AppDelegate.shared.presenterType = "OFF"
            controlPanel.close()
            let completions = finishRecordingLifecycle()
            updateStatusBar()
            completions.forEach { $0() }
        }
    }
    
    static func showPreview(path: String, image: NSImage? = nil) {
        if !ud.bool(forKey: "showPreview") { return }
        var previewImage: NSImage?
        let previewURL = fd.temporaryDirectory.appendingPathComponent("qr-preview.jpg")
        if image == nil { firstFrame?.nsImage?.saveToFile(previewURL, type: .jpeg) }
        
        if let i = image { previewImage = i } else { previewImage = NSImage(contentsOf: previewURL) }
        if let previewImage = previewImage, let screen = getScreenWithMouse() {
            let contentView = NSHostingView(rootView: PreviewView(frame: previewImage, filePath: path))
            previewWindow.contentView = contentView
            previewWindow.setFrameOrigin(NSPoint(x: screen.frame.maxX - 280, y: screen.frame.minY + 20))
            previewWindow.orderFront(self)
        }
    }
    
    static func m4a2mp3(inputUrl: URL, outputUrl: URL) async throws {
        let progress = Progress()
        let lameEncoder = try SwiftLameEncoder(
            sourceUrl: inputUrl,
            configuration: .init(
                sampleRate: .custom(48000),
                bitrateMode: .constant(Int32(ud.integer(forKey: "audioQuality"))),
                quality: .nearBest
            ),
            destinationUrl: outputUrl,
            progress: progress // optional
        )
        try await lameEncoder.encode(priority: .userInitiated)
    }
    
    static func trimVideo() {
        if ud.bool(forKey: "trimAfterRecord") {
            let fileURL = filePath.url
            AppDelegate.shared.createNewWindow(view: VideoTrimmerView(videoURL: fileURL), title: fileURL.lastPathComponent, only: false)
        }
    }
    
    static func getCameras() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        return discoverySession.devices
    }
    
    static func getMicrophone() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return discoverySession.devices.filter({ !$0.localizedName.contains("CADefaultDeviceAggregate") })
    }

    static func microphoneID(for selection: String, devices: [AVCaptureDevice]? = nil) -> String? {
        let selection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return nil }
        if selection == "default" { return selection }

        let devices = devices ?? getMicrophone()
        if let device = devices.first(where: { $0.uniqueID == selection }) {
            return device.uniqueID
        }

        let matchingNames = devices.filter({ $0.localizedName == selection })
        guard matchingNames.count == 1 else { return nil }
        return matchingNames[0].uniqueID
    }

    @discardableResult
    static func migrateMicrophoneSelectionIfNeeded(
        _ selection: String? = nil,
        devices: [AVCaptureDevice]? = nil
    ) -> String {
        let savedSelection = selection ?? ud.string(forKey: "micDevice") ?? "default"
        let resolvedSelection = microphoneID(for: savedSelection, devices: devices) ?? "default"
        if ud.string(forKey: "micDevice") != resolvedSelection {
            ud.set(resolvedSelection, forKey: "micDevice")
        }
        return resolvedSelection
    }

    static func microphoneDisplayName(for device: AVCaptureDevice, devices: [AVCaptureDevice]) -> String {
        let hasDuplicateName = devices.contains(where: {
            $0.uniqueID != device.uniqueID && $0.localizedName == device.localizedName
        })
        guard hasDuplicateName else { return device.localizedName }
        return "\(device.localizedName) — \(device.uniqueID)"
    }
    
    static func getCurrentMic() -> AVCaptureDevice? {
        let devices = getMicrophone()
        let deviceID = migrateMicrophoneSelectionIfNeeded(devices: devices)
        guard deviceID != "default" else { return nil }
        return devices.first(where: { $0.uniqueID == deviceID })
    }
    
    /*static func getChannelCount() -> Int? {
        if let device = getCurrentMic() {
            if let channels = device.formats.first?.formatDescription.audioChannelLayout?.numberOfChannels {
                return channels
            }
            
            let activeFormat = device.activeFormat
            let description = activeFormat.formatDescription
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                let channelCount = audioStreamBasicDescription.mChannelsPerFrame
                return max(2, Int(channelCount))
            }
        }
        return getDefaultChannelCount()
    }
    
    static func getDefaultChannelCount() -> Int? {
        var deviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout.size(ofValue: deviceID))
        
        // 获取默认音频输入设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            print("Failed to get default audio input device")
            return nil
        }
        
        // 获取通道数
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 查询流配置信息
        var streamConfig: UnsafeMutableAudioBufferListPointer?
        propertySize = 0
        
        // 先获取属性大小
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard sizeStatus == noErr else {
            print("Failed to get size for stream configuration")
            return nil
        }
        
        // 分配内存以存储音频流配置
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }
        
        let configStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferList)
        guard configStatus == noErr else {
            print("Failed to get stream configuration")
            return nil
        }
        
        streamConfig = UnsafeMutableAudioBufferListPointer(bufferList)
        
        // 计算通道总数
        var totalChannels = 0
        for buffer in streamConfig! {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return max(2, totalChannels)
    }*/
    
    static func getSampleRate() -> Int? {
        if let device = getCurrentMic() {
            let activeFormat = device.activeFormat
            let description = activeFormat.formatDescription
            
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                let sampleRate = audioStreamBasicDescription.mSampleRate
                return Int(sampleRate)
            }
        }
        return getDefaultSampleRate()
    }
    
    static func getDefaultSampleRate() -> Int? {
        var deviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout.size(ofValue: deviceID))
        
        // 获取默认音频输入设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            print("Failed to get default audio input device")
            return nil
        }
        
        // 获取采样率
        var sampleRate: Double = 0
        propertySize = UInt32(MemoryLayout.size(ofValue: sampleRate))
        
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let sampleRateStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        guard sampleRateStatus == noErr else {
            print("Failed to get sample rate for the default input device")
            return nil
        }
        
        return Int(sampleRate)
    }
    
    static func adjustTime(sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard CMSampleBufferGetFormatDescription(sample) != nil else { return nil }

        var timingEntryCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingEntryCount
        ) == noErr, timingEntryCount > 0 else { return nil }

        var timingInfo = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(),
            count: timingEntryCount
        )
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: timingInfo.count,
            arrayToFill: &timingInfo,
            entriesNeededOut: nil
        ) == noErr else { return nil }

        for index in timingInfo.indices {
            if timingInfo[index].decodeTimeStamp.flags.contains(.valid) {
                timingInfo[index].decodeTimeStamp = CMTimeSubtract(timingInfo[index].decodeTimeStamp, offset)
            }
            if timingInfo[index].presentationTimeStamp.flags.contains(.valid) {
                timingInfo[index].presentationTimeStamp = CMTimeSubtract(timingInfo[index].presentationTimeStamp, offset)
            }
        }

        var outSampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sample,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &outSampleBuffer
        ) == noErr else { return nil }

        return outSampleBuffer
    }
    
    static func showNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification failed to send：\(error.localizedDescription)") }
        }
    }
    
    static func mixAudioTracks(videoURL: URL, videoFormat: String? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        showNotification(title: "Still Processing".local, body: "Mixing audio track...".local, id: "quickrecorder.processing.\(UUID().uuidString)")
        
        let asset = AVAsset(url: videoURL)
        let audioOutputURL = videoURL.deletingPathExtension()
        let outputURL = audioOutputURL.deletingPathExtension()
        let audioOnlyComposition = AVMutableComposition()
        
        let fileEnding = videoFormat ?? ud.string(forKey: "videoFormat") ?? ""
        let fileType: AVFileType
        switch fileEnding {
        case VideoFormat.mov.rawValue: fileType = .mov
        case VideoFormat.mp4.rawValue: fileType = .mp4
        default:
            assertionFailure("loaded unknown video format".local)
            fileType = .mp4
        }
        
        Task { @MainActor in
            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                let assetDuration = try await asset.load(.duration)
                guard audioTracks.count > 1 else {
                    completion(.failure(NSError(domain: "AudioTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not enough audio tracks found."])))
                    return
                }

                for audioTrack in audioTracks {
                    if let compositionAudioTrack = audioOnlyComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: audioTrack, at: .zero)
                    }
                }

                let audioMix = AVMutableAudioMix()
                audioMix.inputParameters = audioTracks.map {
                    let parameters = AVMutableAudioMixInputParameters(track: $0)
                    parameters.trackID = $0.trackID
                    return parameters
                }

                guard let audioExportSession = AVAssetExportSession(asset: audioOnlyComposition, presetName: AVAssetExportPresetHighestQuality) else {
                    completion(.failure(NSError(domain: "AudioExportSessionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio export session."])))
                    return
                }
                audioExportSession.outputURL = audioOutputURL
                audioExportSession.outputFileType = fileType
                audioExportSession.audioMix = audioMix
                try await LegacyAssetExportJob(session: audioExportSession).run()

                let audioAsset = AVAsset(url: audioOutputURL)
                let composition = AVMutableComposition()
                let videoTracks = try await asset.loadTracks(withMediaType: .video)

                guard let videoTrack = videoTracks.first,
                      let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    completion(.failure(NSError(domain: "VideoTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get video track."])))
                    return
                }

                try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: videoTrack, at: .zero)

                let mixedAudioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                guard !mixedAudioTracks.isEmpty else {
                    completion(.failure(NSError(domain: "AudioTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not enough audio tracks found."])))
                    return
                }

                for audioTrack in mixedAudioTracks {
                    if let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration), of: audioTrack, at: .zero)
                    }
                }

                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                    completion(.failure(NSError(domain: "ExportSessionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session."])))
                    return
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = fileType
                exportSession.audioMix = audioMix
                try await LegacyAssetExportJob(session: exportSession).run()

                try? fd.removeItem(at: videoURL)
                try? fd.removeItem(at: audioOutputURL)
                completion(.success(outputURL))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
