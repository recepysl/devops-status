import SwiftUI
import AppKit
import DevOpsKit

struct MenuBarLabel: View {
    @ObservedObject var monitor: StatusMonitor

    var body: some View {
        HStack(spacing: 3) {
            if monitor.setupError != nil && monitor.snapshot == nil {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: "arrow.triangle.pull")
                if let snapshot = monitor.snapshot, snapshot.badgeCount > 0 {
                    Text("\(snapshot.badgeCount)")
                }
            }
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        if monitor.setupError != nil { return .orange }
        guard let snapshot = monitor.snapshot, snapshot.severity != .ok else { return .primary }
        return snapshot.severity.color
    }
}

struct MenuBarView: View {
    @ObservedObject var monitor: StatusMonitor
    var account: Account = .shared

    private let visibleLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.title2)
                .foregroundStyle(headerColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("DevOps Status").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let snapshot = monitor.snapshot {
                badge(snapshot)
            }
        }
    }

    private var headerColor: Color {
        guard let snapshot = monitor.snapshot, snapshot.severity != .ok else { return .accentColor }
        return snapshot.severity.color
    }

    private var subtitle: String {
        let organization = account.organization?.name
        let user = monitor.snapshot?.user
        return [user, organization].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private func badge(_ snapshot: Snapshot) -> some View {
        let text: String
        let reviews = snapshot.toReview.items.count
        let failed = snapshot.failedPipelines.count
        if failed > 0 {
            text = "\(failed) failing"
        } else if reviews > 0 {
            text = "\(reviews) to review"
        } else if snapshot.severity == .ok {
            text = "All clear"
        } else {
            text = "Needs attention"
        }
        let color = snapshot.severity == .ok ? Color.green : snapshot.severity.color
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var content: some View {
        if let error = monitor.setupError, monitor.snapshot == nil || error == DevOpsError.unauthorized.localizedDescription {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings…") { SettingsWindow.show() }
            }
        } else if let snapshot = monitor.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SectionKind.allCases) { kind in
                    sectionView(kind, snapshot)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sectionView(_ kind: SectionKind, _ snapshot: Snapshot) -> some View {
        switch kind {
        case .review:
            section(kind, count: snapshot.toReview.items.count, error: snapshot.toReview.error, severity: snapshot.toReview.items.isEmpty ? .ok : .attention) {
                rows(snapshot.toReview.items, empty: "Nothing waiting for your review") { ReviewRow(pr: $0) }
            }
        case .mine:
            section(kind, count: snapshot.mine.items.count, error: snapshot.mine.error, severity: snapshot.mine.items.map(\.severity).max() ?? .ok) {
                rows(snapshot.mine.items, empty: "No active pull requests") { MyPullRequestRow(pr: $0, me: snapshot.userID) }
            }
        case .pipelines:
            section(kind, count: snapshot.pipelines.items.count, error: snapshot.pipelines.error, severity: snapshot.pipelines.items.map(\.severity).max() ?? .ok) {
                if snapshot.pipelines.items.isEmpty {
                    Button("Choose pipelines to watch…") { SettingsWindow.show() }
                        .buttonStyle(.link).font(.caption)
                } else {
                    rows(snapshot.pipelines.items, empty: "") { PipelineRow(status: $0) }
                }
            }
        case .workItems:
            section(kind, count: snapshot.workItems.items.count, error: snapshot.workItems.error, severity: .ok) {
                rows(snapshot.workItems.items, empty: "Nothing assigned to you") { WorkItemRow(item: $0) }
            }
        }
    }

    private func section<Content: View>(
        _ kind: SectionKind,
        count: Int,
        error: String?,
        severity: Severity,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let collapsed = monitor.isCollapsed(kind)
        return VStack(alignment: .leading, spacing: 6) {
            Button { monitor.toggle(kind) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 10)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(kind.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 6)
                    if error != nil {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill((severity == .ok ? Color.secondary : severity.color).opacity(0.16)))
                        .foregroundStyle(severity == .ok ? Color.secondary : severity.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                Group {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        content()
                    }
                }
                .padding(.leading, 17)
            }
        }
    }

    @ViewBuilder
    private func rows<Item: Identifiable, Row: View>(_ items: [Item], empty: String, @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if items.isEmpty {
            Text(empty).font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.prefix(visibleLimit)) { row($0) }
                if items.count > visibleLimit {
                    Text("+ \(items.count - visibleLimit) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Group {
                if monitor.isStale {
                    Label("Offline · showing last data", systemImage: "wifi.slash").foregroundStyle(.orange)
                } else {
                    Text(monitor.lastUpdated.map { "Updated \(Format.ago($0))" } ?? " ").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            Spacer()
            Button { monitor.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(monitor.isRefreshing)
            .help("Refresh now")
            Button { SettingsWindow.show() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}

struct LinkRow<Leading: View, Trailing: View>: View {
    let url: URL?
    let title: String
    let meta: String
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                leading().frame(width: 12).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    Text(meta).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.vertical, 3).padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
        .help(url == nil ? title : "\(title)\nClick to open in the browser")
    }
}

struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

struct ReviewRow: View {
    let pr: PullRequest

    var body: some View {
        LinkRow(url: pr.url, title: pr.title, meta: meta) {
            Circle().fill(Color.orange).frame(width: 6, height: 6).padding(.top, 3)
        } trailing: {
            if pr.isRequiredReview {
                Chip(text: "Required", color: .orange)
            }
        }
    }

    private var meta: String {
        var parts = [pr.author, "\(pr.repository) → \(pr.shortTargetBranch)"]
        if let age = Format.age(since: pr.createdAt) { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

extension PullRequest {
    var isRequiredReview: Bool {
        reviewers.contains { !$0.isGroup && $0.isRequired && $0.vote == .none && $0.id != authorID }
    }
}

struct MyPullRequestRow: View {
    let pr: PullRequest
    let me: String

    var body: some View {
        LinkRow(url: pr.url, title: pr.title, meta: meta) {
            Circle().fill(pr.severity == .ok ? pr.reviewState.color : pr.severity.color).frame(width: 6, height: 6).padding(.top, 3)
        } trailing: {
            HStack(spacing: 4) {
                if pr.build != .none {
                    Image(systemName: pr.build.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(pr.build.color)
                        .help(pr.build.label ?? "")
                }
                if pr.hasConflicts {
                    Chip(text: "Conflicts", color: .red)
                } else if pr.isDraft {
                    Chip(text: "Draft", color: .secondary)
                } else {
                    Chip(text: stateText, color: pr.reviewState.color)
                }
            }
        }
    }

    private var stateText: String {
        let people = pr.people
        if pr.reviewState == .pending && !people.isEmpty {
            return "\(pr.approvals)/\(people.count) approved"
        }
        return pr.reviewState.label
    }

    private var meta: String {
        var parts = ["\(pr.repository) → \(pr.shortTargetBranch)"]
        if let age = Format.age(since: pr.createdAt) { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

struct PipelineRow: View {
    let status: PipelineStatus

    var body: some View {
        LinkRow(url: status.url, title: status.pipeline.name, meta: meta) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(status.color)
        } trailing: {
            HStack(spacing: 4) {
                if status.isRunning {
                    Chip(text: "Running", color: .blue)
                }
                if status.result != .none || !status.isRunning {
                    Chip(text: status.result.label, color: status.color)
                }
            }
        }
    }

    private var symbol: String {
        switch status.result {
        case .succeeded: return "checkmark"
        case .failed: return "xmark"
        case .partiallySucceeded: return "exclamationmark"
        case .canceled: return "slash.circle"
        case .none: return status.isRunning ? "arrow.triangle.2.circlepath" : "minus"
        }
    }

    private var meta: String {
        var parts = [status.pipeline.projectName]
        if let number = status.buildNumber { parts.append(number) }
        if let branch = status.branch { parts.append(branch) }
        if let age = Format.age(since: status.finishedAt) { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

struct WorkItemRow: View {
    let item: WorkItem

    var body: some View {
        LinkRow(url: item.url, title: item.title, meta: meta) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        } trailing: {
            Chip(text: item.state, color: .secondary)
        }
    }

    private var meta: String {
        var parts = ["\(item.type) #\(item.id)", item.project]
        if let priority = item.priority { parts.append("P\(priority)") }
        if let age = Format.age(since: item.changedAt) { parts.append(age) }
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        switch item.type.lowercased() {
        case "bug": return "ladybug.fill"
        case "task": return "checkmark.square"
        case "user story", "product backlog item", "requirement": return "book.fill"
        case "feature": return "trophy.fill"
        case "epic": return "crown.fill"
        default: return "doc.text"
        }
    }

    private var color: Color {
        switch item.type.lowercased() {
        case "bug": return .red
        case "task": return .yellow
        case "user story", "product backlog item", "requirement": return .blue
        case "feature": return .purple
        case "epic": return .orange
        default: return .secondary
        }
    }
}
