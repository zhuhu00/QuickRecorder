//
//  RecordingLifecycle.swift
//  QuickRecorder
//

struct RecordingLifecycle {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case paused
        case stopping
        case failed
    }

    enum StopRequest: Equatable {
        case cancelStart
        case start
        case join
        case inactive
    }

    private(set) var phase: Phase = .idle

    mutating func beginStart() -> Bool {
        guard phase == .idle || phase == .failed else { return false }
        phase = .starting
        return true
    }

    mutating func completeStart() -> Bool {
        guard phase == .starting else { return false }
        phase = .recording
        return true
    }

    mutating func setPaused(_ paused: Bool) -> Bool {
        if paused {
            guard phase == .recording else { return false }
            phase = .paused
        } else {
            guard phase == .paused else { return false }
            phase = .recording
        }
        return true
    }

    mutating func beginStop() -> Bool {
        requestStop() == .start
    }

    mutating func requestStop() -> StopRequest {
        switch phase {
        case .starting:
            phase = .stopping
            return .cancelStart
        case .recording, .paused:
            phase = .stopping
            return .start
        case .stopping:
            return .join
        case .idle, .failed:
            return .inactive
        }
    }

    mutating func fail() {
        phase = .failed
    }

    mutating func finish() {
        phase = .idle
    }
}
