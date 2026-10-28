import Foundation
import Combine
import DevOpsKit

enum SectionKind: String, CaseIterable, Identifiable {
    case review
    case mine
    case pipelines
    case workItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "To Review"
        case .mine: return "My Pull Requests"
        case .pipelines: return "Pipelines"
        case .workItems: return "Work Items"
        }
    }

    var symbol: String {
        switch self {
        case .review: return "eye"
        case .mine: return "arrow.triangle.pull"
        case .pipelines: return "gearshape.2"
        case .workItems: return "checklist"
        }
    }
}

@MainActor
final class StatusMonitor: ObservableObject {
    static let shared = StatusMonitor()

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var setupError: String?
    @Published private(set) var isStale = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var collapsed: Set<SectionKind> = []

    private let preferences: Preferences
    private let account: Account
    private var timer: Timer?
    private var generation = 0
    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        preferences = .shared
        account = .shared
    }

    init(preview snapshot: Snapshot?, setupError: String? = nil, collapsed: Set<SectionKind> = []) {
        preferences = Preferences(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!)
        account = Account(preferences: preferences, persistent: false)
        self.snapshot = snapshot
        self.setupError = setupError
        self.collapsed = collapsed
    }

    var hasLoaded: Bool {
        snapshot != nil || setupError != nil
    }

    var lastUpdated: Date? {
        snapshot?.fetchedAt
    }

    func start() {
        refreshNow()
        schedule()
        preferences.$interval
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.schedule() } }
            .store(in: &subscriptions)
        preferences.$pipelines
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.refreshNow() } }
            .store(in: &subscriptions)
    }

    func refreshNow() {
        Task { await tick() }
    }

    func reset() {
        generation += 1
        snapshot = nil
        isStale = false
        setupError = DevOpsError.missingToken.localizedDescription
    }

    func isCollapsed(_ section: SectionKind) -> Bool {
        collapsed.contains(section)
    }

    func toggle(_ section: SectionKind) {
        if collapsed.contains(section) {
            collapsed.remove(section)
        } else {
            collapsed.insert(section)
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: preferences.interval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    private func tick() async {
        generation += 1
        let gen = generation
        isRefreshing = true
        defer { if gen == generation { isRefreshing = false } }

        guard let client = account.client() else {
            setupError = account.organization == nil
                ? "Connect your Azure DevOps organization in Settings."
                : DevOpsError.missingToken.localizedDescription
            snapshot = nil
            return
        }

        do {
            let next = try await client.snapshot(pipelines: preferences.pipelines)
            guard gen == generation else { return }
            if preferences.notificationsEnabled, !isStale {
                Notifier.shared.notify(Changes.between(snapshot, next))
            }
            snapshot = next
            setupError = nil
            isStale = false
            account.didLoad(user: next.user)
        } catch {
            guard gen == generation else { return }
            if snapshot == nil || error as? DevOpsError == .unauthorized {
                setupError = error.localizedDescription
            }
            isStale = snapshot != nil
        }
    }
}
