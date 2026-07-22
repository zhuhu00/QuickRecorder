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
        guard phase == .starting || phase == .recording || phase == .paused else { return false }
        phase = .stopping
        return true
    }

    mutating func fail() {
        phase = .failed
    }

    mutating func finish() {
        phase = .idle
    }
}
