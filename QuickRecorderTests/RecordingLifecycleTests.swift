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
