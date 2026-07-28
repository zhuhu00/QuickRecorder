import XCTest
import CoreMedia
@testable import QuickRecorder

final class RecordingLifecycleTests: XCTestCase {
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
        let source = temporaryDirectory.appendingPathComponent("recording.m4a")
        try Data().write(to: source)
        try Data("existing".utf8).write(
            to: temporaryDirectory.appendingPathComponent("recording.txt")
        )

        let urls = TranscriptSidecarWriter.availableURLs(for: source)

        XCTAssertEqual(urls.txt.lastPathComponent, "recording-1.txt")
        XCTAssertEqual(urls.srt.lastPathComponent, "recording-1.srt")
    }

    func testWritesCompleteTXTAndSRTAsAPair() throws {
        let source = temporaryDirectory.appendingPathComponent("recording.m4a")
        try Data().write(to: source)
        let segments = [
            TranscriptSegment(start: 1.25, end: 3.5, text: "你好"),
            TranscriptSegment(start: 3.5, end: 4.75, text: "hello")
        ]

        let urls = try TranscriptSidecarWriter.writePair(
            sourceURL: source,
            text: "你好\n\nhello",
            segments: segments
        )

        XCTAssertEqual(try String(contentsOf: urls.txt, encoding: .utf8), "你好\n\nhello")
        let srt = try String(contentsOf: urls.srt, encoding: .utf8)
        XCTAssertTrue(srt.contains("00:00:01,250 --> 00:00:03,500"))
        XCTAssertTrue(srt.contains("你好"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.srt.path))
    }

    func testSpeakerLabelsAppearOnlyInTXT() throws {
        let source = temporaryDirectory.appendingPathComponent("meeting.m4a")
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

        let urls = try TranscriptSidecarWriter.writePair(
            sourceURL: source,
            text: speakerText,
            segments: subtitleSegments
        )

        let txt = try String(contentsOf: urls.txt, encoding: .utf8)
        let srt = try String(contentsOf: urls.srt, encoding: .utf8)
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
