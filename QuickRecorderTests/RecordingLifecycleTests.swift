import XCTest
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

    func testUnitTestRuntimeDetection() {
        XCTAssertTrue(AppRuntime.detectsUnitTests(in: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]))
        XCTAssertFalse(AppRuntime.detectsUnitTests(in: [:]))
        XCTAssertTrue(AppRuntime.isRunningUnitTests)
    }
}
