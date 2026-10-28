import SwiftUI
import DevOpsKit

extension Severity {
    var color: Color {
        switch self {
        case .ok: return .green
        case .attention: return .orange
        case .critical: return .red
        }
    }
}

extension CheckState {
    var label: String? {
        switch self {
        case .passed: return "Build passed"
        case .failed: return "Build failed"
        case .running: return "Building"
        case .queued: return "Build queued"
        case .none: return nil
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .failed: return .red
        case .running, .queued: return .blue
        case .none: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .queued: return "clock"
        case .none: return "circle"
        }
    }
}

extension ReviewState {
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .approved: return .green
        case .waitingForAuthor: return .orange
        case .rejected: return .red
        }
    }
}

extension PipelineStatus {
    var color: Color {
        if isRunning && result == .none { return .blue }
        switch result {
        case .succeeded: return .green
        case .partiallySucceeded: return .orange
        case .failed: return .red
        case .canceled, .none: return .secondary
        }
    }
}

enum Format {
    static func age(since date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3_600)h ago"
    }

    static func interval(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minute\(seconds == 60 ? "" : "s")"
    }
}
