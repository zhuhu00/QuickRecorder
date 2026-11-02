import XCTest
import CoreMedia
import AVFoundation
@testable import QuickRecorder

final class RecordingLifecycleTests: XCTestCase {
    @MainActor
    func testMicrophoneOnlyAudioWritesWithoutSystemSamples() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickRecorder-mic-routing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = ["saveDirectory", "audioFormat"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        let previousStreamType = SCContext.streamType
        defer {
            SCContext.resetWriterSession(cancelWriting: true)
            SCContext.audioFile = nil
            SCContext.streamType = previousStreamType
            SCContext.startTime = nil
            for (key, value) in zip(keys, previous) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.set(directory.path, forKey: "saveDirectory")
        UserDefaults.standard.set("aac", forKey: "audioFormat")
        SCContext.streamType = .systemaudio
        SCContext.resetWriterSession(cancelWriting: true)
        SCContext.resetRecordingTimeline()
        let app = AppDelegate.shared
        XCTAssertThrowsError(try app.prepareAudioRecording(recordsMicrophone: false, recordsSystemAudio: false))
        let url = try app.prepareAudioRecording(recordsMicrophone: true, recordsSystemAudio: false)
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertNil(SCContext.audioFile)
        let writer = try XCTUnwrap(SCContext.vW)
        let input = try XCTUnwrap(SCContext.micInput)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        for channel in 0..<2 {
            for frame in 0..<4800 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48000)) * 0.1
            }
        }
        SCContext.appendMicrophoneSample(try XCTUnwrap(buffer.asSampleBuffer))
        XCTAssertNotNil(SCContext.startTime)
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    @MainActor
    func testFloatingPanelDragExcludesControlsAndResizeEdges() {
        let panel = RecorderFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        panel.dragRegion = NSRect(x: 0, y: 0, width: 400, height: 80)
        panel.dragExclusions = [NSRect(x: 20, y: 8, width: 100, height: 64)]
        XCTAssertTrue(panel.shouldDrag(at: NSPoint(x: 200, y: 40)))
        XCTAssertTrue(panel.shouldDrag(at: NSPoint(x: 50, y: 76)))
        XCTAssertFalse(panel.shouldDrag(at: NSPoint(x: 50, y: 40)))
        XCTAssertFalse(panel.shouldDrag(at: NSPoint(x: 410, y: 40)))
        panel.styleMask.insert(.resizable)
        XCTAssertFalse(panel.shouldDrag(at: NSPoint(x: 3, y: 40)))
        XCTAssertTrue(panel.shouldDrag(at: NSPoint(x: 200, y: 40)))
    }

    @MainActor
    func testDragRegionUsesCurrentViewSizeAndFlippedCoordinates() {
        let panel = RecorderFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        let surface = RecorderDragSurface.DragView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        panel.contentView = surface
        surface.excludedRects = [NSRect(x: 20, y: 8, width: 100, height: 64)]
        surface.updateDragRegion()
        XCTAssertNotNil(panel.dragSurface)
        XCTAssertTrue(panel.shouldDrag(at: NSPoint(x: 200, y: 40)))
        XCTAssertFalse(panel.shouldDrag(at: NSPoint(x: 50, y: 40)))
        panel.setContentSize(NSSize(width: 500, height: 80))
        XCTAssertTrue(panel.shouldDrag(at: NSPoint(x: 450, y: 40)))
    }

    func testAudioPresenceSkipsSilenceAndFindsLateStereoSound() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickRecorder-sound-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 2))
        for (name, amplitude, start) in [("silent", Float(0), 0), ("near-silent", Float(0.00001), 0), ("late-sound", Float(0.03), 30000)] {
            let url = directory.appendingPathComponent(name + ".wav")
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000))
            buffer.frameLength = 32000
            for frame in 0..<32000 {
                let value = frame >= start ? amplitude * Float(sin(Double(frame) * 2 * .pi * 440 / 16000)) : 0
                buffer.floatChannelData![0][frame] = value
                buffer.floatChannelData![1][frame] = -value
            }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            let result = try await RecordingAudioPresence.hasSound(in: url)
            XCTAssertEqual(result, name == "late-sound", name)
        }
        do {
            _ = try await RecordingAudioPresence.hasSound(in: directory.appendingPathComponent("missing.wav"))
            XCTFail("An unreadable file must not be classified as silence")
        } catch {}
    }

    func testAudioPresenceSkipsVideoWithoutAudioTrack() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QuickRecorder-no-audio-" + UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16
        ])
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixelBuffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels)!, 0, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        XCTAssertTrue(adaptor.append(pixels, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let hasSound = try await RecordingAudioPresence.hasSound(in: url)
        XCTAssertFalse(hasSound)
    }

    func testSuccessfulRecordingLifecycle() {
        var lifecycle = RecordingLifecycle()

        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertEqual(lifecycle.phase, .starting)
        XCTAssertTrue(lifecycle.completeStart())
        XCTAssertEqual(lifecycle.phase, .recording)
        XCTAssertTrue(lifecycle.beginStop())
        XCTAssertEqual(lifecycle.phase, .stopping)

        lifecycle.finish()
        XCTAssertEqual(lifecycle.phase, .idle)
    }

    func testPauseAndResume() {
        var lifecycle = RecordingLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.completeStart())

        XCTAssertTrue(lifecycle.setPaused(true))
        XCTAssertEqual(lifecycle.phase, .paused)
        XCTAssertTrue(lifecycle.setPaused(false))
        XCTAssertEqual(lifecycle.phase, .recording)
    }

    func testDuplicateStopIsRejected() {
        var lifecycle = RecordingLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.completeStart())

        XCTAssertTrue(lifecycle.beginStop())
        XCTAssertFalse(lifecycle.beginStop())
        XCTAssertEqual(lifecycle.phase, .stopping)
    }

    func testDuplicateStopJoinsActiveStop() {
        var lifecycle = RecordingLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.completeStart())

        XCTAssertEqual(lifecycle.requestStop(), .start)
        XCTAssertEqual(lifecycle.requestStop(), .join)
        XCTAssertEqual(lifecycle.phase, .stopping)
    }

    func testStopDuringStartRequestsCancellation() {
        var lifecycle = RecordingLifecycle()
        XCTAssertTrue(lifecycle.beginStart())

        XCTAssertEqual(lifecycle.requestStop(), .cancelStart)
        XCTAssertEqual(lifecycle.requestStop(), .join)
        XCTAssertFalse(lifecycle.completeStart())
        XCTAssertEqual(lifecycle.phase, .stopping)

        lifecycle.finish()
        XCTAssertEqual(lifecycle.phase, .idle)
    }

    func testStopRequestWhenInactiveCompletesImmediately() {
        var lifecycle = RecordingLifecycle()

        XCTAssertEqual(lifecycle.requestStop(), .inactive)
        lifecycle.fail()
        XCTAssertEqual(lifecycle.requestStop(), .inactive)
    }

    func testFailedStartCanRetry() {
        var lifecycle = RecordingLifecycle()
        XCTAssertTrue(lifecycle.beginStart())

        lifecycle.fail()
        XCTAssertEqual(lifecycle.phase, .failed)
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertEqual(lifecycle.phase, .starting)
    }

    func testInvalidTransitionsDoNotChangeState() {
        var lifecycle = RecordingLifecycle()

        XCTAssertFalse(lifecycle.completeStart())
        XCTAssertFalse(lifecycle.setPaused(true))
        XCTAssertFalse(lifecycle.beginStop())
        XCTAssertEqual(lifecycle.phase, .idle)
    }
}

final class QuickRecorderConfigurationTests: XCTestCase {
    func testDefaultEncoderUsesH265() {
        XCTAssertEqual(Encoder.defaultValue, .h265)
    }

    func testTranscriptionDefaultsAreLocalAndOptIn() {
        XCTAssertEqual(TranscriptionStore.modelVariant, "large-v3-v20240930_626MB")
        XCTAssertNil(TranscriptionLanguage.automatic.whisperLanguageCode)
        XCTAssertEqual(TranscriptionLanguage.chinese.whisperLanguageCode, "zh")
        XCTAssertEqual(TranscriptionLanguage.english.whisperLanguageCode, "en")
    }

    func testRecordingIndicatorStyleDefaultsAndMigration() {
        XCTAssertEqual(RecordingIndicatorStyle.defaultValue, .full)
        XCTAssertEqual(
            RecordingIndicatorStyle.resolvedValue(storedRawValue: nil, legacyMiniStatusBar: nil),
            .full
        )
        XCTAssertEqual(
            RecordingIndicatorStyle.resolvedValue(storedRawValue: nil, legacyMiniStatusBar: true),
            .discreet
        )
        XCTAssertEqual(
            RecordingIndicatorStyle.resolvedValue(storedRawValue: "full", legacyMiniStatusBar: true),
            .full
        )
    }

    func testUnitTestRuntimeDetection() {
        XCTAssertTrue(AppRuntime.detectsUnitTests(in: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]))
        XCTAssertFalse(AppRuntime.detectsUnitTests(in: [:]))
        XCTAssertTrue(AppRuntime.isRunningUnitTests)
    }

    func testCompactPreferencesApplyFixedRecordingDefaults() {
        let suiteName = "QuickRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AudioFormat.flac.rawValue, forKey: "audioFormat")
        defaults.set(AudioQuality.extreme.rawValue, forKey: "audioQuality")
        defaults.set(true, forKey: "enableAEC")
        defaults.set(VideoFormat.mov.rawValue, forKey: "videoFormat")
        defaults.set(0.3, forKey: "videoQuality")
        defaults.set(Encoder.h264.rawValue, forKey: "encoder")
        defaults.set(true, forKey: "withAlpha")

        CompactRecorderPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "audioFormat"), AudioFormat.aac.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "audioQuality"), AudioQuality.high.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "enableAEC"))
        XCTAssertEqual(defaults.string(forKey: "videoFormat"), VideoFormat.mov.rawValue)
        XCTAssertEqual(defaults.double(forKey: "videoQuality"), 1.0)
        XCTAssertEqual(defaults.string(forKey: "encoder"), Encoder.h265.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "withAlpha"))
        XCTAssertTrue(defaults.bool(forKey: "remuxAudio"))
        XCTAssertTrue(defaults.bool(forKey: "preventSleep"))
        XCTAssertTrue(defaults.bool(forKey: "hideSelf"))
    }

    func testRecordingCaptureOptionsFollowVisibleControls() {
        XCTAssertTrue(RecordingCaptureOptions.showsCursor(showMouse: true, audioOnly: false))
        XCTAssertFalse(RecordingCaptureOptions.showsCursor(showMouse: false, audioOnly: false))
        XCTAssertFalse(RecordingCaptureOptions.showsCursor(showMouse: true, audioOnly: true))

        XCTAssertTrue(RecordingCaptureOptions.includesMenuBar(for: .screen))
        XCTAssertFalse(RecordingCaptureOptions.includesMenuBar(for: .screenarea))
        XCTAssertFalse(RecordingCaptureOptions.includesMenuBar(for: .window))
        XCTAssertFalse(RecordingCaptureOptions.includesMenuBar(for: .windows))
        XCTAssertFalse(RecordingCaptureOptions.includesMenuBar(for: .systemaudio))
    }

    func testRecordingFileNamesAreSortableAndCollisionSafe() throws {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 28,
                hour: 12,
                minute: 34,
                second: 56
            ))
        )

        XCTAssertEqual(
            RecordingFileNamer.baseName(for: date, capture: false, timeZone: timeZone),
            "Recording_20260728_123456"
        )
        XCTAssertEqual(
            RecordingFileNamer.baseName(for: date, capture: true, timeZone: timeZone),
            "Capture_20260728_123456"
        )
        XCTAssertEqual(
            RecordingFileNamer.availableBaseName(
                for: date,
                capture: false,
                existingFileNames: [
                    "Recording_20260728_123456.mp4",
                    "Recording_20260728_123456-1.qma"
                ],
                timeZone: timeZone
            ),
            "Recording_20260728_123456-2"
        )
    }

    func testCompactPreferencesPreserveSupportedOutputChoices() {
        let suiteName = "QuickRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AudioFormat.mp3.rawValue, forKey: "audioFormat")
        defaults.set(AudioQuality.good.rawValue, forKey: "audioQuality")
        defaults.set(VideoFormat.mov.rawValue, forKey: "videoFormat")
        defaults.set(0.7, forKey: "videoQuality")
        defaults.set(true, forKey: "showOnDock")
        defaults.set(false, forKey: "showMenubar")

        CompactRecorderPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "audioFormat"), AudioFormat.mp3.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "audioQuality"), AudioQuality.good.rawValue)
        XCTAssertEqual(defaults.string(forKey: "videoFormat"), VideoFormat.mov.rawValue)
        XCTAssertEqual(defaults.double(forKey: "videoQuality"), 0.7)
        XCTAssertTrue(defaults.bool(forKey: "showOnDock"))
        XCTAssertFalse(defaults.bool(forKey: "showMenubar"))
    }

    func testCompactPreferencesAlwaysKeepOneReachableEntry() {
        XCTAssertFalse(CompactRecorderPreferences.hasReachableAppEntry(showOnDock: false, showMenubar: false))
        XCTAssertTrue(CompactRecorderPreferences.hasReachableAppEntry(showOnDock: true, showMenubar: false))
        XCTAssertTrue(CompactRecorderPreferences.hasReachableAppEntry(showOnDock: false, showMenubar: true))

        let suiteName = "QuickRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "showOnDock")
        defaults.set(false, forKey: "showMenubar")
        CompactRecorderPreferences.apply(to: defaults)

        XCTAssertTrue(defaults.bool(forKey: "showMenubar"))
    }

    func testMicrophoneSelectionAlwaysResolvesToARealDeviceWhenAvailable() {
        let builtIn = "BuiltInMicrophoneDevice"
        let headset = "ExternalHeadsetDevice"
        let devices = [headset, builtIn]

        XCTAssertEqual(
            SCContext.resolvedMicrophoneSelection(
                "default",
                availableDeviceIDs: devices,
                defaultDeviceID: builtIn
            ),
            builtIn
        )
        XCTAssertEqual(
            SCContext.resolvedMicrophoneSelection(
                headset,
                availableDeviceIDs: devices,
                defaultDeviceID: builtIn
            ),
            headset
        )
        XCTAssertEqual(
            SCContext.resolvedMicrophoneSelection(
                "DisconnectedDevice",
                availableDeviceIDs: devices,
                defaultDeviceID: builtIn
            ),
            builtIn
        )
        XCTAssertEqual(
            SCContext.resolvedMicrophoneSelection(
                "default",
                availableDeviceIDs: [],
                defaultDeviceID: nil
            ),
            "default"
        )
    }
}

final class TranscriptSidecarWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSidecarNamesShareTheSameCollisionSuffix() throws {
        let source = temporaryDirectory.appendingPathComponent("recording.mp4")
        try Data().write(to: source)
        try Data("existing".utf8).write(
            to: temporaryDirectory.appendingPathComponent("recording.txt")
        )

        let urls = TranscriptSidecarWriter.availableURLs(for: source)

        XCTAssertEqual(urls.txt.lastPathComponent, "recording-1.txt")
        XCTAssertEqual(urls.srt?.lastPathComponent, "recording-1.srt")
    }

    func testVideoAvoidsExistingSRTWhenChoosingBothNames() throws {
        let source = temporaryDirectory.appendingPathComponent("recording.MOV")
        try Data("existing".utf8).write(
            to: temporaryDirectory.appendingPathComponent("recording.srt")
        )

        let urls = TranscriptSidecarWriter.availableURLs(for: source)

        XCTAssertEqual(urls.txt.lastPathComponent, "recording-1.txt")
        XCTAssertEqual(urls.srt?.lastPathComponent, "recording-1.srt")
    }

    func testAudioWritesTXTAndSRTWithoutOverwritingExistingFiles() throws {
        for fileExtension in ["m4a", "MP3"] {
            let source = temporaryDirectory.appendingPathComponent("recording-\(fileExtension).\(fileExtension)")
            let existingSRT = source.deletingPathExtension().appendingPathExtension("srt")
            try Data("existing subtitles".utf8).write(to: existingSRT)
            let text = "[00:00:01 - 00:00:03] Speaker A: 你好"

            let urls = try TranscriptSidecarWriter.write(
                sourceURL: source,
                text: text,
                segments: [TranscriptSegment(start: 1, end: 3, text: "你好")]
            )

            XCTAssertEqual(urls.txt.lastPathComponent, "recording-\(fileExtension)-1.txt")
            let srtURL = try XCTUnwrap(urls.srt)
            XCTAssertEqual(srtURL.lastPathComponent, "recording-\(fileExtension)-1.srt")
            let srt = try String(contentsOf: srtURL, encoding: .utf8)
            XCTAssertEqual(srt, "1\n00:00:01,000 --> 00:00:03,000\n你好\n")
            XCTAssertEqual(try String(contentsOf: urls.txt, encoding: .utf8), text)
            XCTAssertEqual(try String(contentsOf: existingSRT, encoding: .utf8), "existing subtitles")

            let repeatedURLs = try TranscriptSidecarWriter.write(sourceURL: source, text: "second", segments: [])
            XCTAssertEqual(repeatedURLs.txt.lastPathComponent, "recording-\(fileExtension)-2.txt")
            XCTAssertEqual(repeatedURLs.srt?.lastPathComponent, "recording-\(fileExtension)-2.srt")
            XCTAssertEqual(try String(contentsOf: urls.txt, encoding: .utf8), text)
            XCTAssertEqual(try String(contentsOf: srtURL, encoding: .utf8), srt)
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertEqual(files.count, 10) // Two existing SRT files and four new TXT/SRT pairs.
    }

    func testWritesCompleteTXTAndSRTAsAPair() throws {
        let source = temporaryDirectory.appendingPathComponent("recording.mp4")
        try Data().write(to: source)
        let segments = [
            TranscriptSegment(start: 1.25, end: 3.5, text: "你好"),
            TranscriptSegment(start: 3.5, end: 4.75, text: "hello")
        ]

        let urls = try TranscriptSidecarWriter.write(
            sourceURL: source,
            text: "你好\n\nhello",
            segments: segments
        )

        XCTAssertEqual(try String(contentsOf: urls.txt, encoding: .utf8), "你好\n\nhello")
        let srtURL = try XCTUnwrap(urls.srt)
        let srt = try String(contentsOf: srtURL, encoding: .utf8)
        XCTAssertTrue(srt.contains("00:00:01,250 --> 00:00:03,500"))
        XCTAssertTrue(srt.contains("你好"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: srtURL.path))
    }

    func testSpeakerLabelsAppearOnlyInTXT() throws {
        let source = temporaryDirectory.appendingPathComponent("meeting.mov")
        try Data().write(to: source)
        let subtitleSegments = [
            TranscriptSegment(start: 1, end: 3, text: "你好"),
            TranscriptSegment(start: 3, end: 5, text: "hello")
        ]
        let speakerText = SpeakerTranscriptFormatter.text(
            for: [
                SpeakerTranscriptSegment(start: 1, end: 3, speaker: "A", text: "你好"),
                SpeakerTranscriptSegment(start: 3, end: 5, speaker: "B", text: "hello")
            ]
        )

        let urls = try TranscriptSidecarWriter.write(
            sourceURL: source,
            text: speakerText,
            segments: subtitleSegments
        )

        let txt = try String(contentsOf: urls.txt, encoding: .utf8)
        let srt = try String(contentsOf: XCTUnwrap(urls.srt), encoding: .utf8)
        XCTAssertTrue(txt.contains("Speaker A: 你好"))
        XCTAssertTrue(txt.contains("Speaker B: hello"))
        XCTAssertFalse(srt.contains("Speaker A"))
        XCTAssertFalse(srt.contains("Speaker B"))
        XCTAssertTrue(srt.contains("你好"))
        XCTAssertTrue(srt.contains("hello"))
    }
}

final class WriterSessionGateTests: XCTestCase {
    func testSamplesAreRejectedUntilSessionOpens() {
        var gate = WriterSessionGate()
        let sessionStart = CMTime(value: 100, timescale: 1_000)

        XCTAssertFalse(gate.accepts(sessionStart))
        XCTAssertTrue(gate.open(at: sessionStart))
        XCTAssertTrue(gate.accepts(sessionStart))
        XCTAssertTrue(gate.accepts(CMTime(value: 101, timescale: 1_000)))
    }

    func testSamplesBeforeSessionStartAreRejected() {
        var gate = WriterSessionGate()
        let sessionStart = CMTime(value: 100, timescale: 1_000)

        XCTAssertTrue(gate.open(at: sessionStart))
        XCTAssertFalse(gate.accepts(CMTime(value: 99, timescale: 1_000)))
        XCTAssertFalse(gate.open(at: CMTime(value: 200, timescale: 1_000)))
    }

    func testClosingSessionRejectsLaterSamples() {
        var gate = WriterSessionGate()
        let sessionStart = CMTime(value: 100, timescale: 1_000)

        XCTAssertTrue(gate.open(at: sessionStart))
        gate.close()
        XCTAssertFalse(gate.isOpen)
        XCTAssertFalse(gate.accepts(CMTime(value: 101, timescale: 1_000)))
    }
}
