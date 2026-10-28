import Foundation
import DevOpsKit

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let intervals: [TimeInterval] = [30, 60, 120, 300]

    @Published var organization: String {
        didSet { defaults.set(organization, forKey: Keys.organization) }
    }
    @Published var pipelines: [PipelineRef] {
        didSet { defaults.set(try? JSONEncoder().encode(pipelines), forKey: Keys.pipelines) }
    }
    @Published var interval: TimeInterval {
        didSet { defaults.set(interval, forKey: Keys.interval) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let organization = "organization"
        static let pipelines = "pipelines"
        static let interval = "refreshInterval"
        static let notifications = "notificationsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        organization = defaults.string(forKey: Keys.organization) ?? ""
        pipelines = defaults.data(forKey: Keys.pipelines).flatMap { try? JSONDecoder().decode([PipelineRef].self, from: $0) } ?? []
        let savedInterval = defaults.double(forKey: Keys.interval)
        interval = Self.intervals.contains(savedInterval) ? savedInterval : 60
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
    }

    func isWatching(_ pipeline: PipelineRef) -> Bool {
        pipelines.contains { $0.id == pipeline.id }
    }

    func setWatching(_ pipeline: PipelineRef, _ watching: Bool) {
        pipelines.removeAll { $0.id == pipeline.id }
        if watching {
            pipelines.append(pipeline)
            pipelines.sort { ($0.projectName, $0.name.lowercased()) < ($1.projectName, $1.name.lowercased()) }
        }
    }
}
