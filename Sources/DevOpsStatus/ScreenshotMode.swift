import AppKit
import SwiftUI
import DevOpsKit

@MainActor
enum ScreenshotMode {
    static func run(outputPath: String) -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for theme in Theme.allCases {
                try write(HeroScene(monitor: DemoData.busy(), theme: theme), to: output, name: "hero", theme: theme)
                try write(StatesScene(theme: theme), to: output, name: "states", theme: theme)
                try write(SettingsScene(theme: theme), to: output, name: "settings", theme: theme)
                try write(MenuBarStripScene(theme: theme), to: output, name: "menubar", theme: theme)
            }
        } catch {
            FileHandle.standardError.write("✗ screenshot rendering failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        print("✓ Rendered screenshots to \(output.path)")
        exit(0)
    }

    private static func write<V: View>(_ view: V, to directory: URL, name: String, theme: Theme) throws {
        let rep = snapshot(view, appearance: theme.appearance)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: directory.appendingPathComponent("\(name)-\(theme.rawValue).png"))
    }

    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance, scale: CGFloat = 2) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

enum Theme: String, CaseIterable {
    case light
    case dark

    var appearance: NSAppearance {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)!
    }

    var backdrop: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(
                colors: [Color(red: 0.80, green: 0.88, blue: 1.00), Color(red: 0.90, green: 0.92, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.22), Color(red: 0.10, green: 0.12, blue: 0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var menuBarFill: Color {
        self == .light ? Color.white.opacity(0.55) : Color.black.opacity(0.35)
    }
}

@MainActor
enum DemoData {
    static let now = Date()
    static let me = "me"
    static let organization = Organization("contoso")!

    static func url(_ path: String) -> URL {
        organization.url.appendingPathComponent(path)
    }

    static func person(_ id: String, _ vote: Vote = .none, required: Bool = false) -> Reviewer {
        Reviewer(id: id, name: names[id] ?? id, vote: vote, isRequired: required)
    }

    static let names = [
        "ada": "Ada Lovelace",
        "alan": "Alan Turing",
        "grace": "Grace Hopper",
        "linus": "Linus Torvalds",
        "barbara": "Barbara Liskov",
        me: "Margaret Hamilton",
    ]

    static func review(_ id: Int, _ title: String, by author: String, repo: String, age: TimeInterval, required: Bool = false) -> PullRequest {
        PullRequest(
            id: id, title: title, project: "Web Shop", repository: repo,
            author: names[author] ?? author, authorID: author,
            createdAt: now.addingTimeInterval(-age),
            reviewers: [person(me, required: required)],
            url: url("Web Shop/_git/\(repo)/pullrequest/\(id)")
        )
    }

    static func mine(_ id: Int, _ title: String, repo: String, reviewers: [Reviewer], build: CheckState, conflicts: Bool = false, age: TimeInterval) -> PullRequest {
        PullRequest(
            id: id, title: title, project: "Web Shop", repository: repo,
            author: names[me]!, authorID: me,
            createdAt: now.addingTimeInterval(-age),
            hasConflicts: conflicts,
            reviewers: reviewers,
            url: url("Web Shop/_git/\(repo)/pullrequest/\(id)"),
            build: build
        )
    }

    static func pipeline(_ id: Int, _ name: String, _ result: RunResult, running: Bool = false, number: String, by: String = "ada", age: TimeInterval) -> PipelineStatus {
        PipelineStatus(
            pipeline: PipelineRef(projectID: "web", projectName: "Web Shop", definitionID: id, name: name),
            result: result, isRunning: running, buildNumber: number, branch: "main",
            requestedBy: names[by], finishedAt: now.addingTimeInterval(-age),
            url: url("Web Shop/_build/results")
        )
    }

    static func item(_ id: Int, _ title: String, _ type: String, _ state: String, priority: Int, age: TimeInterval) -> WorkItem {
        WorkItem(id: id, title: title, type: type, state: state, project: "Web Shop", priority: priority,
                 changedAt: now.addingTimeInterval(-age), url: url("Web Shop/_workitems/edit/\(id)"))
    }

    static func busySnapshot() -> Snapshot {
        Snapshot(
            user: names[me]!,
            userID: me,
            toReview: .init(items: [
                review(4821, "Retry card payments on gateway timeouts", by: "ada", repo: "checkout-api", age: 25 * 60, required: true),
                review(4817, "Cache product images at the edge", by: "linus", repo: "storefront", age: 3 * 3_600),
                review(4809, "Upgrade to .NET 9", by: "grace", repo: "inventory-service", age: 26 * 3_600),
            ]),
            mine: .init(items: [
                mine(4824, "Add order export to CSV", repo: "backoffice", reviewers: [person("ada", .approved), person("alan", .approved)], build: .passed, age: 2 * 3_600),
                mine(4815, "Split tax rules per region", repo: "checkout-api", reviewers: [person("grace", .waitingForAuthor), person("alan")], build: .passed, age: 20 * 3_600),
                mine(4802, "Move search to the new index", repo: "storefront", reviewers: [person("barbara", .approved), person("linus")], build: .failed, conflicts: true, age: 3 * 86_400),
            ]),
            pipelines: .init(items: [
                pipeline(12, "checkout-api-ci", .failed, number: "20261028.7", by: "ada", age: 12 * 60),
                pipeline(14, "storefront-ci", .succeeded, running: true, number: "20261028.15", age: 40 * 60),
                pipeline(21, "nightly-e2e", .partiallySucceeded, number: "20261028.1", age: 8 * 3_600),
                pipeline(30, "deploy-production", .succeeded, number: "20261027.3", by: "grace", age: 19 * 3_600),
            ]),
            workItems: .init(items: [
                item(9182, "Saved cards fail at checkout on Safari", "Bug", "Active", priority: 1, age: 50 * 60),
                item(9170, "Export orders as CSV", "User Story", "Active", priority: 2, age: 5 * 3_600),
                item(9166, "Write runbook for gateway outages", "Task", "New", priority: 3, age: 2 * 86_400),
            ]),
            fetchedAt: now.addingTimeInterval(-12)
        )
    }

    static func busy() -> StatusMonitor {
        StatusMonitor(preview: busySnapshot())
    }

    static func clear() -> StatusMonitor {
        StatusMonitor(preview: Snapshot(
            user: names[me]!,
            userID: me,
            mine: .init(items: [
                mine(4824, "Add order export to CSV", repo: "backoffice", reviewers: [person("ada", .approved), person("alan", .approved)], build: .passed, age: 2 * 3_600),
            ]),
            pipelines: .init(items: [
                pipeline(12, "checkout-api-ci", .succeeded, number: "20261028.8", age: 5 * 60),
                pipeline(14, "storefront-ci", .succeeded, number: "20261028.15", age: 30 * 60),
                pipeline(30, "deploy-production", .succeeded, number: "20261027.3", by: "grace", age: 19 * 3_600),
            ]),
            workItems: .init(items: [
                item(9170, "Export orders as CSV", "User Story", "Active", priority: 2, age: 5 * 3_600),
            ]),
            fetchedAt: now.addingTimeInterval(-12)
        ))
    }

    static func reviewsOnly() -> StatusMonitor {
        var snapshot = busySnapshot()
        snapshot.pipelines.items = snapshot.pipelines.items.filter { $0.result != .failed && $0.result != .partiallySucceeded }
        snapshot.mine.items = snapshot.mine.items.filter { $0.severity == .ok }
        snapshot.toReview.items = Array(snapshot.toReview.items.prefix(2))
        return StatusMonitor(preview: snapshot, collapsed: [.workItems])
    }

    static func signedOut() -> StatusMonitor {
        StatusMonitor(preview: nil, setupError: DevOpsError.unauthorized.localizedDescription)
    }

    static func preferences() -> Preferences {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!)
        preferences.organization = organization.url.absoluteString
        preferences.pipelines = pipelineRefs.filter { [12, 14, 21, 30].contains($0.definitionID) }
        return preferences
    }

    static let projects = [Project(id: "web", name: "Web Shop"), Project(id: "data", name: "Data Platform")]

    static let pipelineRefs: [PipelineRef] = [
        (12, "checkout-api-ci"), (13, "checkout-api-pr"), (14, "storefront-ci"), (16, "inventory-service-ci"),
        (21, "nightly-e2e"), (30, "deploy-production"), (31, "deploy-staging"),
    ].map { PipelineRef(projectID: "web", projectName: "Web Shop", definitionID: $0.0, name: $0.1) }

    static func picker(_ account: Account) -> PipelinePicker {
        PipelinePicker(account: account, preview: projects, pipelines: ["web": pipelineRefs])
    }
}

struct DropdownPanel: View {
    let monitor: StatusMonitor
    let account: Account

    var body: some View {
        MenuBarView(monitor: monitor, account: account)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }

    @MainActor
    init(monitor: StatusMonitor) {
        self.monitor = monitor
        self.account = Account(preferences: DemoData.preferences(), persistent: false, previewUser: DemoData.names[DemoData.me])
    }
}

struct FakeMenuBar: View {
    let monitor: StatusMonitor
    let theme: Theme

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            MenuBarLabel(monitor: monitor)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Text("Wed 9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(theme.menuBarFill)
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.06, green: 0.15, blue: 0.38)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}

struct HeroScene: View {
    let monitor: StatusMonitor
    let theme: Theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.backdrop
            VStack(spacing: 0) {
                FakeMenuBar(monitor: monitor, theme: theme)
                HStack(alignment: .top) {
                    tagline
                        .padding(.leading, 64)
                        .padding(.top, 120)
                    Spacer()
                    DropdownPanel(monitor: monitor)
                        .padding(.trailing, 110)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 1040, height: 790)
    }

    private var tagline: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppIconView(size: 88)
            Text("DevOps Status")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Reviews, pull requests,\npipelines and work items —\nright in your menu bar.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                pill("Native SwiftUI")
                pill("Azure DevOps")
                pill("macOS 14+")
            }
            .padding(.top, 6)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.menuBarFill))
    }
}

struct StatesScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            HStack(alignment: .top, spacing: 36) {
                caption("All clear", DemoData.clear())
                caption("Token expired", DemoData.signedOut())
            }
            .padding(48)
        }
        .fixedSize()
    }

    private func caption(_ title: String, _ monitor: StatusMonitor) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            DropdownPanel(monitor: monitor)
        }
    }
}

struct SettingsScene: View {
    let theme: Theme

    var body: some View {
        let preferences = DemoData.preferences()
        let account = Account(preferences: preferences, persistent: false, previewUser: DemoData.names[DemoData.me])
        ZStack {
            theme.backdrop
            SettingsView(preferences: preferences, account: account, picker: DemoData.picker(account), login: .shared)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(48)
        }
        .fixedSize()
    }
}

struct MenuBarStripScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            HStack(spacing: 28) {
                chip(DemoData.clear())
                chip(DemoData.reviewsOnly())
                chip(DemoData.busy())
                chip(DemoData.signedOut())
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .fixedSize()
    }

    private func chip(_ monitor: StatusMonitor) -> some View {
        MenuBarLabel(monitor: monitor)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.menuBarFill))
    }
}
