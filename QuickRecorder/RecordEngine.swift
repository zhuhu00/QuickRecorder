//
//  RecordEngine.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/17.
//

import Foundation
import UserNotifications
import ScreenCaptureKit
import AVFoundation
import AVFAudio
import VideoToolbox
import AECAudioStream

private enum RecordingStartError: LocalizedError {
    case missingOutputDirectory
    case missingShareableContent
    case missingDisplay
    case missingSelection(String)
    case unsupportedFormat(String)
    case outputAlreadyExists(String)
    case cannotAddWriterInput(String)
    case writerStartFailed(String)
    case microphoneUnavailable
    case microphoneConfigurationFailed(String)
    case microphoneStartFailed

    var errorDescription: String? {
        switch self {
        case .missingOutputDirectory:
            return "No output folder is configured.".local
        case .missingShareableContent:
            return "Screen capture content is unavailable. Please try again.".local
        case .missingDisplay:
            return "The selected display is no longer available.".local
        case .missingSelection(let selection):
            return String(format: "The selected %@ is no longer available.".local, selection.local)
        case .unsupportedFormat(let format):
            return String(format: "Unsupported recording format: %@".local, format)
        case .outputAlreadyExists(let path):
            return String(format: "A recording already exists at: %@".local, path)
        case .cannotAddWriterInput(let input):
            return String(format: "Unable to prepare the %@ recording track.".local, input.local)
        case .writerStartFailed(let message):
            return String(format: "Unable to start the recording writer: %@".local, message)
        case .microphoneUnavailable:
            return "The selected microphone is no longer available.".local
        case .microphoneConfigurationFailed(let message):
            return String(format: "Unable to configure the microphone: %@".local, message)
        case .microphoneStartFailed:
            return "Unable to start the selected microphone.".local
        }
    }
}

extension AppDelegate {
    @objc func prepRecord(type: String, screens: SCDisplay?, windows: [SCWindow]?, fastStart: Bool = false) {
        prepRecord(
            type: type,
            displayID: screens?.displayID,
            windowIDs: windows?.map(\.windowID),
            fastStart: fastStart
        )
    }

    func prepRecord(
        type: String,
        displayID: CGDirectDisplayID?,
        windowIDs: [CGWindowID]?,
        fastStart: Bool = false,
        recordMicrophoneOverride: Bool? = nil
    ) {
        guard SCContext.streamType == nil,
              ["window", "windows", "display", "area", "audio"].contains(type) else { return }

        SCContext.updateAvailableContent {
            guard SCContext.streamType == nil else { return }
            self.prepareRecord(
                type: type,
                displayID: displayID,
                windowIDs: windowIDs,
                fastStart: fastStart,
                recordMicrophoneOverride: recordMicrophoneOverride
            )
        }
    }

    private func prepareRecord(
        type: String,
        displayID: CGDirectDisplayID?,
        windowIDs: [CGWindowID]?,
        fastStart: Bool,
        recordMicrophoneOverride: Bool?
    ) {
        switch type {
        case "window":  SCContext.streamType = .window
        case "windows":  SCContext.streamType = .windows
        case "display": SCContext.streamType = .screen
        case "area": SCContext.streamType = .screenarea
        case "audio":   SCContext.streamType = .systemaudio
            default: return // if we don't even know what to record I don't think we should even try
        }
        SCContext.filter = nil
        SCContext.screen = nil
        SCContext.window = nil

        var isDirectory: ObjCBool = false
        guard let outputPath = saveDirectory, !outputPath.isEmpty else {
            failRecordingPreparation(RecordingStartError.missingOutputDirectory)
            return
        }
        if fd.fileExists(atPath: outputPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                failRecordingPreparation(message: "The output path is a file instead of a folder!".local)
                return
            }
        } else {
            do {
                try fd.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                failRecordingPreparation(message: "Unable to create output folder!".local)
                return
            }
        }

        guard let availableContent = SCContext.availableContent else {
            failRecordingPreparation(RecordingStartError.missingShareableContent)
            return
        }
        
        // file preparation
        guard let displayID,
              let screen = availableContent.displays.first(where: {
                  $0.displayID == displayID
              }) else {
            failRecordingPreparation(RecordingStartError.missingDisplay)
            return
        }
        SCContext.screen = screen
        
        if let windowIDs {
            let matchedWindows = windowIDs.compactMap { windowID in
                availableContent.windows.first(where: { $0.windowID == windowID })
            }
            guard matchedWindows.count == windowIDs.count else {
                failRecordingPreparation(RecordingStartError.missingSelection("window"))
                return
            }
            SCContext.window = matchedWindows
        } else if SCContext.streamType == .window || SCContext.streamType == .windows {
            failRecordingPreparation(RecordingStartError.missingSelection("window"))
            return
        }
        
        let qrWindows = SCContext.getSelfWindows()
        let dockApp = availableContent.applications.first(where: { $0.bundleIdentifier.description == "com.apple.dock" })
        let wallpaper = availableContent.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "com.apple.dock" && title != "LPSpringboard" && title != "Dock"
        })
        let desktop = availableContent.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "" && title == "Desktop"
        })
        let desktopFiles = availableContent.windows.filter({
            $0.owningApplication?.bundleIdentifier == "com.apple.finder"
            && $0.title == "" && $0.frame == screen.frame })
        let controlCenterWindow = availableContent.applications.filter({ $0.bundleIdentifier == "com.apple.controlcenter" })
        let mouseWindow = availableContent.windows.filter({ $0.title == "Mouse Pointer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        let camLayer = availableContent.windows.filter({ $0.title == "Camera Overlayer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        var appBlackList = [String]()
        if let savedData = ud.data(forKey: "hiddenApps"),
           let decodedApps = try? JSONDecoder().decode([AppInfo].self, from: savedData) {
            appBlackList = (decodedApps as [AppInfo]).map({ $0.bundleID })
        }
        let excliudedApps = availableContent.applications.filter({ appBlackList.contains($0.bundleIdentifier) })
        
        if SCContext.streamType == .window || SCContext.streamType == .windows {
            if var includ = SCContext.window {
                guard !includ.isEmpty else {
                    failRecordingPreparation(RecordingStartError.missingSelection("window"))
                    return
                }
                if includ.count > 1 {
                    if highlightMouse { includ += mouseWindow }
                    if background.rawValue == BackgroundType.wallpaper.rawValue { if dockApp != nil { includ += wallpaper }}
                    SCContext.filter = SCContentFilter(display: screen, including: includ + camLayer)
                } else {
                    SCContext.streamType = .window
                    SCContext.filter = SCContentFilter(desktopIndependentWindow: includ[0])
                }
            }
        } else {
            if SCContext.streamType == .screen || SCContext.streamType == .screenarea {
                if SCContext.streamType == .screenarea {
                    if let area = SCContext.screenArea, let name = screen.nsScreen?.localizedName {
                        let a = ["x": area.origin.x, "y": area.origin.y, "width": area.width, "height": area.height]
                        ud.set([name: a], forKey: "savedArea")
                    }
                }
                var excluded = [SCRunningApplication]()
                var except = [SCWindow]()
                excluded += excliudedApps
                if hideCCenter { excluded += controlCenterWindow }
                if hideSelf { if let qrWindows = qrWindows { except += qrWindows }}
                if background.rawValue != BackgroundType.wallpaper.rawValue { if dockApp != nil {
                    except += wallpaper
                    except += desktop
                }}
                if hideDesktopFiles { except += desktopFiles }
                SCContext.filter = SCContentFilter(display: screen, excludingApplications: excluded, exceptingWindows: except)
            }
        }
        if SCContext.streamType == .systemaudio {
            SCContext.filter = SCContentFilter(display: screen, excludingApplications: [], exceptingWindows: [])
        }
        SCContext.filter?.includeMenuBar = RecordingCaptureOptions.includesMenuBar(for: SCContext.streamType)
        guard let filter = SCContext.filter else {
            failRecordingPreparation(message: "Unable to prepare the selected recording source.".local)
            return
        }
        Task {
            await record(
                filter: filter,
                fastStart: fastStart,
                recordMicrophoneOverride: recordMicrophoneOverride
            )
        }
    }

    private func failRecordingPreparation(_ error: Error) {
        failRecordingPreparation(message: error.localizedDescription)
    }

    private func failRecordingPreparation(message: String) {
        SCContext.filter = nil
        SCContext.screen = nil
        SCContext.window = nil
        SCContext.streamType = nil
        _ = createAlert(title: "Failed to Record".local, message: message, button1: "OK").runModal()
        updateStatusBar()
    }

    func record(
        filter: SCContentFilter,
        fastStart: Bool = true,
        recordMicrophoneOverride: Bool? = nil
    ) async {
        SCContext.resetRecordingTimeline()
        
        let audioOnly = SCContext.streamType == .systemaudio
        let shouldRecordMicrophone = recordMicrophoneOverride ?? recordMic
        let selectedMicrophone = shouldRecordMicrophone
            ? SCContext.migrateMicrophoneSelectionIfNeeded(micDevice)
            : micDevice
        let selectedAEC = enableAEC
        var activeStream: SCStream?
        var createdOutputURL: URL?
        var microphoneStarted = false
        var captureStartAttempted = false
        guard SCContext.beginRecordingStart() else { return }
        SCContext.resetWriterSession(cancelWriting: true)

        do {
        
        let conf: SCStreamConfiguration
#if compiler(>=6.0)
        if recordHDR {
            if #available(macOS 15, *) {
                // TODO change here. https://developer.apple.com/videos/play/wwdc2024/10088/?time=191
                // For canonical display, it means you are capturing HDR content that is optimized for sharing with other HDR devices.
                // hdrLocalDisplay or hdrCanonicalDisplay


                conf = SCStreamConfiguration(preset: .captureHDRStreamLocalDisplay)
            } else { conf = SCStreamConfiguration() }
        } else { conf = SCStreamConfiguration() }
#else
        conf = SCStreamConfiguration()
#endif
        conf.width = 2
        conf.height = 2
        conf.showsCursor = RecordingCaptureOptions.showsCursor(showMouse: showMouse, audioOnly: audioOnly)
        
        if !audioOnly {
            conf.width = Int(filter.contentRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
            conf.height = Int(filter.contentRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)

            if background.rawValue != BackgroundType.wallpaper.rawValue { conf.backgroundColor = SCContext.getBackgroundColor() }
            if !recordHDR {
                conf.pixelFormat = kCVPixelFormatType_32BGRA
                conf.colorSpaceName = CGColorSpace.sRGB
                //if withAlpha { conf.pixelFormat = kCVPixelFormatType_32BGRA }
            } else {
                // For recording HDR in a BT2020 PQ container
                conf.colorSpaceName = CGColorSpace.itur_2100_PQ
//                https://developer.apple.com/videos/play/wwdc2022/10155/ guide on how to record 4k60
//                streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    
// Note: 420 encoding causes color bleed at edges, e.g. youtube settings icon with red logo
                // conf.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
//              dont exceed 8 frames  https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
//                lower queuedepth has more stutter, dont go below 4 https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example/blob/main/Sources/sckrecording/main.swift
                conf.queueDepth = 8
            }
        }
        
        conf.capturesAudio = recordWinSound || fastStart || audioOnly
        conf.sampleRate = 48000
        conf.channelCount = 2
        

        let frameIntervalScale = audioOnly ? CMTimeScale.max : CMTimeScale(max(frameRate, 1))
        conf.minimumFrameInterval = CMTime(value: 1, timescale: frameIntervalScale)

//        CMTimeScale is the denominator in the fraction
//        conf.minimumFrameInterval = CMTime(seconds: audioOnly ? Double(CMTimeScale.max) : Double(1)/Double(frameRate), preferredTimescale: 10000)

        // note: ScreenCaptureKit only delivers frames when something changes
        // https://www.reddit.com/r/swift/comments/158n4c9/comment/ju847rm/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button

        //blog post from the reddit comment https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit/

        //https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example

        // https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
        // minimumFrameInterval throttles delivery to the frame rate selected in the UI.

        print("Frame interval passed to ScreenCaptureKit. (timescale is FPS): \(conf.minimumFrameInterval)")
        

        if SCContext.streamType == .screenarea {
            if let nsRect = SCContext.screenArea {
                guard let display = SCContext.screen else {
                    throw RecordingStartError.missingDisplay
                }
                let newY = display.frame.height - nsRect.size.height - nsRect.origin.y
                conf.sourceRect = CGRect(x: nsRect.origin.x, y: newY, width: nsRect.size.width, height: nsRect.size.height)
                conf.width = Int(conf.sourceRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                conf.height = Int(conf.sourceRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
            }
        }
        
        let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
        if !audioOnly && !encoderIsH265 {
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: nil,
                width: Int32(conf.width),
                height: Int32(conf.height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true] as CFDictionary,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &session
            )
            
            if status != noErr {
                let button = showAlertSyncOnMainThread(
                    level: .critical,
                    title: "Encoder Warning",
                    message: "VideoToolbox H.264 hardware encoder doesn't support the current resolution.\nContinue with a software encoder will significantly increase the CPU usage.\n\nWould you like to use H.265 instead?".local,
                    button1: "Use H.265",
                    button2: "Continue with H.264"
                )
                if button == .alertFirstButtonReturn { encoder = .h265 }
            }
        }
        
        let stream = SCStream(filter: filter, configuration: conf, delegate: self)
        activeStream = stream
        SCContext.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: SCContext.streamOutputQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: SCContext.streamOutputQueue)
        if audioOnly {
            createdOutputURL = try prepareAudioRecording(recordsMicrophone: shouldRecordMicrophone)
        } else {
            createdOutputURL = try initVideo(conf: conf, recordsMicrophone: shouldRecordMicrophone)
        }
        if shouldRecordMicrophone {
            try startMicRecording(microphoneDevice: selectedMicrophone, enableAEC: selectedAEC)
            microphoneStarted = true
        }
        guard !SCContext.isStopping else {
            await rollbackRecordingStart(
                stream: activeStream,
                outputURL: createdOutputURL,
                microphoneStarted: microphoneStarted,
                captureStartAttempted: false,
                error: nil,
                treatingAsCancellation: true
            )
            return
        }
        captureStartAttempted = true
        try await stream.startCapture()
        guard SCContext.completeRecordingStart() else {
            await rollbackRecordingStart(
                stream: activeStream,
                outputURL: createdOutputURL,
                microphoneStarted: microphoneStarted,
                captureStartAttempted: captureStartAttempted,
                error: nil,
                treatingAsCancellation: true
            )
            return
        }
        } catch {
            await rollbackRecordingStart(
                stream: activeStream,
                outputURL: createdOutputURL,
                microphoneStarted: microphoneStarted,
                captureStartAttempted: captureStartAttempted,
                error: error,
                treatingAsCancellation: false
            )
            return
        }
        let finishStartWork = DispatchWorkItem { [weak self] in
            guard let self, !SCContext.isStopping else { return }
            if !audioOnly { self.registerGlobalMouseMonitor() }
            updateStatusBar()
            if self.preventSleep {
                SleepPreventer.shared.preventSleep(reason: "Screen recording in progress")
            }
        }
        DispatchQueue.main.async(execute: finishStartWork)
    }

    func prepareAudioRecording(recordsMicrophone: Bool) throws -> URL {
        var fileEnding = audioFormat.rawValue
        var fileType = AVFileType.m4a
        let encorder = fileEnding == AudioFormat.mp3.rawValue ? "aac" : fileEnding
        switch fileEnding { // todo: I'd like to store format info differently
            case AudioFormat.mp3.rawValue: fallthrough
            case AudioFormat.aac.rawValue: fallthrough
            case AudioFormat.alac.rawValue: fileEnding = "m4a"
            case AudioFormat.flac.rawValue: fileEnding = "flac"; fileType = .caf
            case AudioFormat.opus.rawValue: fileEnding = "ogg"; fileType = .caf
            default: throw RecordingStartError.unsupportedFormat(fileEnding)
        }
        let path = SCContext.getFilePath()
        if recordsMicrophone && SCContext.streamType == .systemaudio {
            SCContext.filePath = "\(path).qma"
            SCContext.filePath1 = "\(path).qma/sys.\(fileEnding)"
            SCContext.filePath2 = "\(path).qma/mic.\(fileEnding)"
            let packageURL = SCContext.filePath.url
            let infoJsonURL = "\(path).qma/info.json".url
            let jsonString = "{\"format\": \"\(fileEnding)\", \"encoder\": \"\(encorder)\", \"exportMP3\": \(audioFormat.rawValue == AudioFormat.mp3.rawValue), \"sysVol\": 1.0, \"micVol\": 1.0}"
            guard !fd.fileExists(atPath: packageURL.path) else {
                throw RecordingStartError.outputAlreadyExists(packageURL.path)
            }
            do {
                try fd.createDirectory(at: packageURL, withIntermediateDirectories: false, attributes: nil)
                try jsonString.write(to: infoJsonURL, atomically: true, encoding: .utf8)
                SCContext.audioFile = try AVAudioFile(
                    forWriting: SCContext.filePath1.url,
                    settings: SCContext.updateAudioSettings(),
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )

                let sampleRate = SCContext.getSampleRate() ?? 48000
                let settings = SCContext.updateAudioSettings(rate: sampleRate)
                let writer = try AVAssetWriter(outputURL: SCContext.filePath2.url, fileType: fileType)
                SCContext.vW = writer
                let microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                microphoneInput.expectsMediaDataInRealTime = true
                guard writer.canAdd(microphoneInput) else {
                    throw RecordingStartError.cannotAddWriterInput("microphone")
                }
                writer.add(microphoneInput)
                guard writer.startWriting() else {
                    throw RecordingStartError.writerStartFailed(writer.error?.localizedDescription ?? "Unknown Error".local)
                }
                SCContext.micInput = microphoneInput
                return packageURL
            } catch {
                SCContext.audioFile = nil
                SCContext.resetWriterSession(cancelWriting: true)
                try? fd.removeItem(at: packageURL)
                throw error
            }
        } else {
            SCContext.filePath = "\(path).\(fileEnding)"
            SCContext.filePath1 = SCContext.filePath
            let outputURL = SCContext.filePath.url
            guard !fd.fileExists(atPath: outputURL.path) else {
                throw RecordingStartError.outputAlreadyExists(outputURL.path)
            }
            do {
                SCContext.audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: SCContext.updateAudioSettings(),
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                return outputURL
            } catch {
                SCContext.audioFile = nil
                try? fd.removeItem(at: outputURL)
                throw error
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    var isMainScreen: Bool {
        guard let id = self.displayID else { return false }
        return (CGDisplayIsMain(id) == 1)
    }
}

extension SCDisplay {
    var nsScreen: NSScreen? {
        return NSScreen.screens.first(where: { $0.displayID == self.displayID })
    }
}

extension AppDelegate {
    func initVideo(conf: SCStreamConfiguration, recordsMicrophone: Bool) throws -> URL {
        SCContext.startTime = nil

        let fileEnding = videoFormat.rawValue
        let fileType: AVFileType
        switch fileEnding {
            case VideoFormat.mov.rawValue: fileType = AVFileType.mov
            case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
            default: throw RecordingStartError.unsupportedFormat(fileEnding)
        }

        if remuxAudio && recordsMicrophone && recordWinSound {
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding).\(fileEnding).\(fileEnding)"
        } else {
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
        }
        let outputURL = SCContext.filePath.url
        guard !fd.fileExists(atPath: outputURL.path) else {
            throw RecordingStartError.outputAlreadyExists(outputURL.path)
        }

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
            SCContext.vW = writer

            let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
            let fpsMultiplier: Double = Double(frameRate)/8
            let encoderMultiplier: Double = encoderIsH265 ? 0.5 : 0.9
            let resolution = Double(max(600, conf.width)) * Double(max(600, conf.height))
            var qualityMultiplier = 1 - (log10(sqrt(resolution) * fpsMultiplier) / 5)
            switch videoQuality {
                case 0.3: qualityMultiplier = max(0.1, qualityMultiplier)
                case 0.7: qualityMultiplier = max(0.4, min(0.6, qualityMultiplier * 3))
                default: qualityMultiplier = 1.0
            }
            let h264Level = AVVideoProfileLevelH264HighAutoLevel
            let h265Level = recordHDR ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel

            let targetBitrate = resolution * fpsMultiplier * encoderMultiplier * qualityMultiplier * (recordHDR ? 2 : 1)
            print("framerate set in app: \(frameRate)")
            print("target bitrate: \(targetBitrate/1000000)")

            var videoSettings: [String: Any] = [
                AVVideoCodecKey: encoderIsH265 ? ((withAlpha && !recordHDR) ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.hevc) : AVVideoCodecType.h264,
                // yes, not ideal if we want more than these encoders in the future, but it's ok for now
                AVVideoWidthKey: conf.width,
                AVVideoHeightKey: conf.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: encoderIsH265 ? h265Level : h264Level,
                    AVVideoAverageBitRateKey: max(200000, Int(targetBitrate)),
                    AVVideoExpectedSourceFrameRateKey: frameRate,
                ] as [String : Any]
            ]

            if !recordHDR {
                videoSettings[AVVideoColorPropertiesKey] = [
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2] as [String : Any]
            }

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else {
                throw RecordingStartError.cannotAddWriterInput("video")
            }
            writer.add(videoInput)
            SCContext.vwInput = videoInput

            let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: SCContext.updateAudioSettings())
            systemAudioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(systemAudioInput) else {
                throw RecordingStartError.cannotAddWriterInput("system audio")
            }
            writer.add(systemAudioInput)
            SCContext.awInput = systemAudioInput

            if recordsMicrophone {
                let sampleRate = SCContext.getSampleRate() ?? 48000
                let settings = SCContext.updateAudioSettings(rate: sampleRate)
                let microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                microphoneInput.expectsMediaDataInRealTime = true
                guard writer.canAdd(microphoneInput) else {
                    throw RecordingStartError.cannotAddWriterInput("microphone")
                }
                writer.add(microphoneInput)
                SCContext.micInput = microphoneInput
            }

            guard writer.startWriting() else {
                throw RecordingStartError.writerStartFailed(writer.error?.localizedDescription ?? "Unknown Error".local)
            }
            return outputURL
        } catch {
            SCContext.resetWriterSession(cancelWriting: true)
            try? fd.removeItem(at: outputURL)
            throw error
        }
    }
    
    func startMicRecording(microphoneDevice: String, enableAEC: Bool) throws {
        if microphoneDevice == "default" {
            if enableAEC {
                var level = AUVoiceIOOtherAudioDuckingLevel.mid
                switch AECLevel {
                    case "min": level = .min
                    case "max": level = .max
                    default: level = .mid
                }
                do {
                    try SCContext.AECEngine.startAudioStream(enableAEC: enableAEC, duckingLevel: level, audioBufferHandler: { pcmBuffer in
                        guard let sampleBuffer = pcmBuffer.asSampleBuffer else { return }
                        SCContext.appendMicrophoneSample(sampleBuffer)
                    })
                    SCContext.setMicrophoneCaptureMode(.defaultInputWithAEC)
                } catch {
                    try? SCContext.AECEngine.stopAudioUnit()
                    throw error
                }
            } else {
                let input = SCContext.audioEngine.inputNode
                let inputFormat = input.inputFormat(forBus: 0)
                guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                    throw RecordingStartError.microphoneUnavailable
                }
                input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
                    guard let sampleBuffer = buffer.asSampleBuffer else { return }
                    SCContext.appendMicrophoneSample(sampleBuffer)
                }
                do {
                    try SCContext.audioEngine.start()
                    SCContext.setMicrophoneCaptureMode(.defaultInput)
                } catch {
                    input.removeTap(onBus: 0)
                    SCContext.audioEngine.stop()
                    throw error
                }
            }
        } else {
            do {
                try AudioRecorder.shared.setupAudioCapture(deviceID: microphoneDevice)
                SCContext.setMicrophoneCaptureMode(.selectedDevice)
                try AudioRecorder.shared.start()
            } catch {
                SCContext.stopMicrophoneCapture()
                ud.set("default", forKey: "micDevice")
                try startMicRecording(microphoneDevice: "default", enableAEC: enableAEC)
                SCContext.migrateMicrophoneSelectionIfNeeded("default")
                SCContext.showNotification(
                    title: "Microphone Changed".local,
                    body: "The selected microphone is unavailable. Recording will use the default microphone.".local,
                    id: "quickrecorder.microphone-fallback.\(UUID().uuidString)"
                )
            }
        }
    }

    func handleSelectedMicrophoneDisconnect() {
        guard SCContext.streamType != nil,
              !SCContext.isStopping,
              SCContext.isCapturingSelectedMicrophone() else { return }

        SCContext.stopMicrophoneCapture()
        ud.set("default", forKey: "micDevice")
        do {
            try startMicRecording(microphoneDevice: "default", enableAEC: enableAEC)
            SCContext.migrateMicrophoneSelectionIfNeeded("default")
            SCContext.showNotification(
                title: "Microphone Changed".local,
                body: "The selected microphone was disconnected. Recording continues with the default microphone.".local,
                id: "quickrecorder.microphone-fallback.\(UUID().uuidString)"
            )
        } catch {
            SCContext.setMicrophoneCaptureMode(.none)
            SCContext.showNotification(
                title: "Microphone Disconnected".local,
                body: "The default microphone is unavailable. System audio and video recording will continue without the microphone.".local,
                id: "quickrecorder.microphone-disconnected.\(UUID().uuidString)"
            )
        }
    }

    private func rollbackRecordingStart(
        stream: SCStream?,
        outputURL: URL?,
        microphoneStarted: Bool,
        captureStartAttempted: Bool,
        error: Error?,
        treatingAsCancellation: Bool
    ) async {
        SCContext.resetWriterSession(cancelWriting: true)
        if captureStartAttempted, let stream {
            try? await stream.stopCapture()
        }
        SCContext.streamOutputQueue.sync {}

        if microphoneStarted {
            SCContext.stopMicrophoneCapture()
        }

        SCContext.audioFile = nil
        SCContext.audioFile2 = nil

        if let outputURL, fd.fileExists(atPath: outputURL.path) {
            do {
                try fd.removeItem(at: outputURL)
            } catch {
                print("Unable to remove failed recording output at \(outputURL.path): \(error.localizedDescription)")
            }
        }
        SCContext.filePath = nil
        SCContext.filePath1 = nil
        SCContext.filePath2 = nil

        await MainActor.run {
            let cancelled = treatingAsCancellation || SCContext.isStopping
            SCContext.filter = nil
            SCContext.stream = nil
            SCContext.streamType = nil
            SCContext.screen = nil
            SCContext.window = nil
            SCContext.startTime = nil
            SCContext.firstFrame = nil
            SCContext.lastPTS = nil
            SCContext.timePassed = 0
            SCContext.resetRecordingTimeline()
            PopoverState.shared.isPaused = false
            updateStatusBar()
            if cancelled {
                SCContext.completeRecordingStartCancellation()
            } else {
                SCContext.failRecordingStart()
                _ = createAlert(
                    level: .critical,
                    title: "Failed to Record".local,
                    message: error?.localizedDescription ?? "Unknown Error".local,
                    button1: "OK"
                ).runModal()
            }
        }
    }
    
    func outputVideoEffectDidStart(for stream: SCStream) {
        DispatchQueue.main.async { camWindow.close() }
        print("[Presenter Overlay ON]")
        isPresenterON = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
            self.isCameraReady = true
        }
    }
    
    func outputVideoEffectDidStop(for stream: SCStream) {
        print("[Presenter Overlay OFF]")
        presenterType = "OFF"
        isPresenterON = false
        isCameraReady = false
        DispatchQueue.main.async {
            if SCContext.stream != nil { camWindow.orderFront(self) }
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        if SCContext.saveFrame, let imageBuffer = sampleBuffer.imageBuffer {
            SCContext.saveFrame = false
            
            var ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let url = "\(SCContext.getFilePath(capture: true)).png".url
            if !recordHDR {
                sampleBuffer.nsImage?.saveToFile(url)
            } else {
                let context = CIContext()
                
                // Create the HEIF destination with the correct UTI
                //            if let destination = url? {
                // Specify format and color space (assuming default settings here)
                //                let format = CIFormat.rgb10
                let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
                
                // let colorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                
                // Image exposure needs to be increased by one stop to match the original
                ciImage = ciImage.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.0])
                
                
                
                
                
                //                context.writeHEIF10Representation(of: ciImage, to: destination as! URL, colorSpace: colorSpace)
                do{
                    // try context.writeHEIF10Representation(of:ciImage,
                    //                                       to:url,
                    //                                       colorSpace:colorSpace,
                    //                                       options: [
                    //     kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
                    try context.writePNGRepresentation(of:ciImage,
                                                       to:url,
                                                       format: .RGB10,
                                                       colorSpace:colorSpace)
                    //        try context.writePNGRepresentation(of:outImage, to:outURL, format: .RGBA16,colorSpace:colorSpace,options:[:])
                } catch let error {
                    // Handle the error case
                    print("Error: \(error)")
                }
                //                CGImageDestinationFinalize(destination)
            }
        }
        guard sampleBuffer.isValid else { return }
        guard let SampleBuffer = SCContext.sampleBufferForRecording(sampleBuffer) else { return }
        switch outputType {
        case .screen:
            if (SCContext.screen == nil && SCContext.window == nil) || SCContext.streamType == .systemaudio { break }
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(SampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first else { return }
            guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else { return }
            
            if SCContext.vW != nil && SCContext.vW?.status == .writing, SCContext.startTime == nil {
                let sourceTime = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
                guard SCContext.startWriterSessionIfNeeded(at: sourceTime) else { return }
                SCContext.startTime = Date.now
            }
            var pts = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
            let dur = CMSampleBufferGetDuration(SampleBuffer)
            if (dur.value > 0) { pts = CMTimeAdd(pts, dur) }
            if frameQueue.getArray().contains(where: { $0 >= pts }) { print("Skip this frame"); return } else { frameQueue.append(pts) }
            SCContext.lastPTS = pts
            if SCContext.vwInput.isReadyForMoreMediaData {
                if let rect = attachments[.presenterOverlayContentRect] as? [String: Any] {
                    var type = "np"
                    let off = (rect["X"] as! CGFloat == .infinity)
                    let small = (rect["X"] as! CGFloat == 0.0)
                    let big = (!off && !small)
                    if off { type = "OFF" } else if small { type = "Small" } else if big { type = "Big" }
                    if type != presenterType {
                        print("Presenter Overlay set to \"\(type)\"!")
                        isCameraReady = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
                            self.isCameraReady = true
                        }
                        presenterType = type
                    }
                }
                if isPresenterON && !isCameraReady { break }
                if SCContext.firstFrame == nil { SCContext.firstFrame = SampleBuffer }
                SCContext.vwInput.append(SampleBuffer)
            }
            break
        case .audio:
            if SCContext.streamType == .systemaudio { // write directly to file if not video recording
                hideMousePointer = true
                if SCContext.vW != nil && SCContext.vW?.status == .writing, SCContext.startTime == nil {
                    let sourceTime = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
                    guard SCContext.startWriterSessionIfNeeded(at: sourceTime) else { return }
                }
                if SCContext.startTime == nil { SCContext.startTime = Date.now }
                guard let samples = SampleBuffer.asPCMBuffer else { return }
                do { try SCContext.audioFile?.write(from: samples) }
                catch { assertionFailure("audio file writing issue".local) }
            } else {
                if SCContext.lastPTS == nil { return }
                if SCContext.awInput.isReadyForMoreMediaData { SCContext.awInput.append(SampleBuffer) }
            }
#if compiler(>=6.0)
        case .microphone:
            break
#endif
        @unknown default:
            assertionFailure("unknown stream type".local)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        print("closing stream with error:\n".local, error,
              "\nthis might be due to the window closing or the user stopping from the sonoma ui".local)
        DispatchQueue.main.async {
            guard !SCContext.isStartingCapture, SCContext.stream === stream else { return }
            SCContext.stopRecording(streamError: error)
        }
    }
}

class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = AudioRecorder()
    private var captureSession: AVCaptureSession?
    private var audioInput: AVCaptureDeviceInput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private let audioQueue = DispatchQueue(label: "io.github.zhuhu00.QuickRecorder.microphone-output")

    func setupAudioCapture(deviceID: String) throws {
        NotificationCenter.default.removeObserver(self, name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        let session = AVCaptureSession()

        guard let audioDevice = SCContext.getMicrophone().first(where: { $0.uniqueID == deviceID }) else {
            throw RecordingStartError.microphoneUnavailable
        }
        
        // Create audio input
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: audioDevice) }
        catch { throw RecordingStartError.microphoneConfigurationFailed(error.localizedDescription) }
        
        // Add audio input to capture session
        guard session.canAddInput(input) else {
            throw RecordingStartError.microphoneConfigurationFailed("Unable to add the microphone input.".local)
        }
        session.addInput(input)

        // Create audio data output
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)
        
        // Add audio data output to capture session
        guard session.canAddOutput(output) else {
            output.setSampleBufferDelegate(nil, queue: nil)
            throw RecordingStartError.microphoneConfigurationFailed("Unable to add the microphone output.".local)
        }
        session.addOutput(output)

        captureSession = session
        audioInput = input
        audioDataOutput = output
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioDeviceWasDisconnected(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: audioDevice
        )
    }
    
    func start() throws {
        guard let session = captureSession else {
            throw RecordingStartError.microphoneStartFailed
        }
        session.startRunning()
        guard session.isRunning else {
            stopAndDrain()
            throw RecordingStartError.microphoneStartFailed
        }
    }
    
    func stopAndDrain() {
        NotificationCenter.default.removeObserver(self, name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        if let session = captureSession {
            if session.isRunning { session.stopRunning() }
        }
        audioQueue.sync {}
        audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        captureSession = nil
        audioInput = nil
        audioDataOutput = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        SCContext.appendMicrophoneSample(sampleBuffer)
    }

    @objc private func audioDeviceWasDisconnected(_ notification: Notification) {
        DispatchQueue.main.async {
            AppDelegate.shared.handleSelectedMicrophoneDisconnect()
        }
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
// For Sonoma updated to https://developer.apple.com/forums/thread/727709
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
    
    var nsImage: NSImage? {
        return autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let ciContext = CIContext()
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            return nil
        }
    }
}

// Based on https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
extension AVAudioPCMBuffer {
    var asSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
