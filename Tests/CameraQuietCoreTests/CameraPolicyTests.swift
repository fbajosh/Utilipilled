import Foundation
import CameraQuietCore
struct CameraPolicyTests {
    func testConcurrentCamerasAndIdleDebounce() throws {
        var p = CameraPolicy(); let t: TimeInterval = 1_000
        XCTAssertTrue(try p.update(runningCount: 2, reliable: true, now: t))
        XCTAssertTrue(try p.update(runningCount: 1, reliable: true, now: t + 2))
        XCTAssertTrue(try p.update(runningCount: 0, reliable: true, now: t + 3))
        XCTAssertTrue(try p.update(runningCount: 1, reliable: true, now: t + 4))
        XCTAssertTrue(try p.update(runningCount: 0, reliable: true, now: t + 5))
        XCTAssertFalse(try p.update(runningCount: 0, reliable: true, now: t + 6.5))
    }
    func testUnknownIsNotIdleAndEventuallyFails() throws {
        var p = CameraPolicy(); let t: TimeInterval = 1_000
        _ = try p.update(runningCount: 1, reliable: true, now: t)
        XCTAssertTrue(try p.update(runningCount: 0, reliable: false, now: t))
        XCTAssertTrue(try p.update(runningCount: 0, reliable: false, now: t + 4))
        XCTAssertThrowsError(try p.update(runningCount: 0, reliable: false, now: t + 5))
    }
    func testKnownActiveCameraWinsOverAnotherUnreadableCamera() throws {
        var p = CameraPolicy(); let t: TimeInterval = 1_000
        XCTAssertTrue(try p.update(runningCount: 1, reliable: false, now: t))
        XCTAssertTrue(try p.update(runningCount: 1, reliable: false, now: t + 20))
    }
    func testIdleAndUnknownDeadlinesUseElapsedTime() throws {
        // A large monotonic starting point makes the test independent of calendar
        // epoch or time-zone changes. Exact deadline boundaries must still work.
        let t: TimeInterval = 9_000_000
        var p = CameraPolicy()
        XCTAssertTrue(try p.update(runningCount: 1, reliable: true, now: t))
        XCTAssertTrue(try p.update(runningCount: 0, reliable: true, now: t + 10))
        XCTAssertTrue(try p.update(runningCount: 0, reliable: true, now: t + 11.49))
        XCTAssertFalse(try p.update(runningCount: 0, reliable: true, now: t + 11.5))
        _ = try p.update(runningCount: 0, reliable: false, now: t + 20)
        XCTAssertFalse(try p.update(runningCount: 0, reliable: false, now: t + 24.99))
        XCTAssertThrowsError(try p.update(runningCount: 0, reliable: false, now: t + 25))
    }
}
