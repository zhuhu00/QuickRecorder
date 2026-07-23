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
        defaults.set(true, forKey: "includeMenuBar")
        defaults.set(true, forKey: "enableAEC")
        defaults.set(VideoFormat.mov.rawValue, forKey: "videoFormat")
        defaults.set(Encoder.h264.rawValue, forKey: "encoder")
        defaults.set(true, forKey: "withAlpha")

        CompactRecorderPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "audioFormat"), AudioFormat.aac.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "audioQuality"), AudioQuality.high.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "includeMenuBar"))
        XCTAssertFalse(defaults.bool(forKey: "enableAEC"))
        XCTAssertEqual(defaults.string(forKey: "videoFormat"), VideoFormat.mp4.rawValue)
        XCTAssertEqual(defaults.string(forKey: "encoder"), Encoder.h265.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "withAlpha"))
        XCTAssertTrue(defaults.bool(forKey: "remuxAudio"))
        XCTAssertTrue(defaults.bool(forKey: "preventSleep"))
        XCTAssertTrue(defaults.bool(forKey: "hideSelf"))
    }

    func testCompactPreferencesPreserveSupportedAudioChoices() {
        let suiteName = "QuickRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AudioFormat.mp3.rawValue, forKey: "audioFormat")
        defaults.set(AudioQuality.good.rawValue, forKey: "audioQuality")
        defaults.set(true, forKey: "showOnDock")
        defaults.set(false, forKey: "showMenubar")

        CompactRecorderPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "audioFormat"), AudioFormat.mp3.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "audioQuality"), AudioQuality.good.rawValue)
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
