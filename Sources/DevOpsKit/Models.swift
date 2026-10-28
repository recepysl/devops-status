import Foundation

public enum Severity: Int, Comparable, Sendable {
    case ok
    case attention
    case critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum Vote: Int, Sendable {
    case rejected = -10
    case waitingForAuthor = -5
    case none = 0
    case approvedWithSuggestions = 5
    case approved = 10

    public init(score: Int) {
        self = Vote(rawValue: score) ?? (score > 0 ? .approved : score < 0 ? .rejected : .none)
    }

    public var isApproval: Bool {
        self == .approved || self == .approvedWithSuggestions
    }

    public var label: String {
        switch self {
        case .rejected: return "Rejected"
        case .waitingForAuthor: return "Waiting for author"
        case .none: return "No vote"
        case .approvedWithSuggestions: return "Approved with suggestions"
        case .approved: return "Approved"
        }
    }
}

public struct Reviewer: Hashable, Sendable {
    public let id: String
    public let name: String
    public let vote: Vote
    public let isRequired: Bool
    public let isGroup: Bool
    public let hasDeclined: Bool

    public init(id: String, name: String, vote: Vote, isRequired: Bool = false, isGroup: Bool = false, hasDeclined: Bool = false) {
        self.id = id
        self.name = name
        self.vote = vote
        self.isRequired = isRequired
        self.isGroup = isGroup
        self.hasDeclined = hasDeclined
    }
}

public enum CheckState: Int, Comparable, Sendable {
    case passed
    case none
    case queued
    case running
    case failed

    public static func < (lhs: CheckState, rhs: CheckState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(policyStatus: String?) {
        switch policyStatus?.lowercased() {
        case "approved": self = .passed
        case "running": self = .running
        case "queued": self = .queued
        case "rejected", "broken": self = .failed
        default: self = .none
        }
    }
}

public struct PullRequest: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let project: String
    public let projectID: String
    public let repository: String
    public let author: String
    public let authorID: String
    public let createdAt: Date?
    public let isDraft: Bool
    public let hasConflicts: Bool
    public let sourceBranch: String
    public let targetBranch: String
    public let reviewers: [Reviewer]
    public let url: URL?
    public var build: CheckState

    public init(
        id: Int,
        title: String,
        project: String,
        projectID: String = "",
        repository: String,
        author: String,
        authorID: String = "",
        createdAt: Date? = nil,
        isDraft: Bool = false,
        hasConflicts: Bool = false,
        sourceBranch: String = "",
        targetBranch: String = "main",
        reviewers: [Reviewer] = [],
        url: URL? = nil,
        build: CheckState = .none
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.projectID = projectID
        self.repository = repository
        self.author = author
        self.authorID = authorID
        self.createdAt = createdAt
        self.isDraft = isDraft
        self.hasConflicts = hasConflicts
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.reviewers = reviewers
        self.url = url
        self.build = build
    }

    public func vote(of userID: String) -> Vote? {
        reviewers.first { $0.id == userID }.map(\.vote)
    }

    public func awaitsReview(from userID: String) -> Bool {
        guard !isDraft, authorID != userID,
              let me = reviewers.first(where: { $0.id == userID }) else { return false }
        return me.vote == .none && !me.hasDeclined
    }

    public var people: [Reviewer] {
        reviewers.filter { !$0.isGroup && $0.id != authorID }
    }

    public var approvals: Int {
        people.filter(\.vote.isApproval).count
    }

    public var reviewState: ReviewState {
        let votes = reviewers.map(\.vote)
        if votes.contains(.rejected) { return .rejected }
        if votes.contains(.waitingForAuthor) { return .waitingForAuthor }
        let required = reviewers.filter { $0.isRequired && !$0.isGroup }
        if required.contains(where: { !$0.vote.isApproval }) { return .pending }
        return approvals > 0 ? .approved : .pending
    }

    public var severity: Severity {
        if hasConflicts || build == .failed || reviewState == .rejected { return .critical }
        if reviewState == .waitingForAuthor { return .attention }
        return .ok
    }

    public var shortTargetBranch: String {
        Self.shortBranch(targetBranch)
    }

    public static func shortBranch(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }
}

public enum ReviewState: Sendable {
    case pending
    case approved
    case waitingForAuthor
    case rejected

    public var label: String {
        switch self {
        case .pending: return "In review"
        case .approved: return "Approved"
        case .waitingForAuthor: return "Waiting for author"
        case .rejected: return "Rejected"
        }
    }
}

public struct PipelineRef: Codable, Hashable, Sendable, Identifiable {
    public let projectID: String
    public let projectName: String
    public let definitionID: Int
    public let name: String

    public var id: String { "\(projectID)/\(definitionID)" }

    public init(projectID: String, projectName: String, definitionID: Int, name: String) {
        self.projectID = projectID
        self.projectName = projectName
        self.definitionID = definitionID
        self.name = name
    }
}

public enum RunResult: String, Sendable {
    case succeeded
    case partiallySucceeded
    case failed
    case canceled
    case none

    public init(_ raw: String?) {
        self = raw.flatMap(RunResult.init(rawValue:)) ?? .none
    }

    public var label: String {
        switch self {
        case .succeeded: return "Succeeded"
        case .partiallySucceeded: return "Partially succeeded"
        case .failed: return "Failed"
        case .canceled: return "Canceled"
        case .none: return "No runs"
        }
    }
}

public struct PipelineStatus: Identifiable, Hashable, Sendable {
    public let pipeline: PipelineRef
    public let result: RunResult
    public let isRunning: Bool
    public let buildNumber: String?
    public let branch: String?
    public let requestedBy: String?
    public let finishedAt: Date?
    public let url: URL?

    public var id: String { pipeline.id }

    public init(
        pipeline: PipelineRef,
        result: RunResult,
        isRunning: Bool = false,
        buildNumber: String? = nil,
        branch: String? = nil,
        requestedBy: String? = nil,
        finishedAt: Date? = nil,
        url: URL? = nil
    ) {
        self.pipeline = pipeline
        self.result = result
        self.isRunning = isRunning
        self.buildNumber = buildNumber
        self.branch = branch
        self.requestedBy = requestedBy
        self.finishedAt = finishedAt
        self.url = url
    }

    public var severity: Severity {
        switch result {
        case .failed: return .critical
        case .partiallySucceeded: return .attention
        default: return .ok
        }
    }
}

public struct WorkItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let type: String
    public let state: String
    public let project: String
    public let priority: Int?
    public let changedAt: Date?
    public let url: URL?

    public init(id: Int, title: String, type: String, state: String, project: String, priority: Int? = nil, changedAt: Date? = nil, url: URL? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.state = state
        self.project = project
        self.priority = priority
        self.changedAt = changedAt
        self.url = url
    }
}

public struct Section<Item: Sendable>: Sendable {
    public var items: [Item]
    public var error: String?

    public init(items: [Item] = [], error: String? = nil) {
        self.items = items
        self.error = error
    }
}

public struct Snapshot: Sendable {
    public var user: String
    public var userID: String
    public var toReview: Section<PullRequest>
    public var mine: Section<PullRequest>
    public var pipelines: Section<PipelineStatus>
    public var workItems: Section<WorkItem>
    public var fetchedAt: Date

    public init(
        user: String = "",
        userID: String = "",
        toReview: Section<PullRequest> = .init(),
        mine: Section<PullRequest> = .init(),
        pipelines: Section<PipelineStatus> = .init(),
        workItems: Section<WorkItem> = .init(),
        fetchedAt: Date = Date()
    ) {
        self.user = user
        self.userID = userID
        self.toReview = toReview
        self.mine = mine
        self.pipelines = pipelines
        self.workItems = workItems
        self.fetchedAt = fetchedAt
    }

    public var failedPipelines: [PipelineStatus] {
        pipelines.items.filter { $0.result == .failed }
    }

    public var badgeCount: Int {
        toReview.items.count + failedPipelines.count
    }

    public var severity: Severity {
        let worst = (mine.items.map(\.severity) + pipelines.items.map(\.severity)).max() ?? .ok
        if worst == .critical { return .critical }
        if !toReview.items.isEmpty || worst == .attention { return .attention }
        return .ok
    }

    public var hasErrors: Bool {
        [toReview.error, mine.error, pipelines.error, workItems.error].contains { $0 != nil }
    }
}

public enum Change: Equatable, Sendable {
    case reviewRequested(PullRequest)
    case voted(PullRequest, by: String, Vote)
    case pipelineFailed(PipelineStatus)
    case workItemAssigned(WorkItem)

    public static func == (lhs: Change, rhs: Change) -> Bool {
        lhs.key == rhs.key
    }

    public var key: String {
        switch self {
        case .reviewRequested(let pr): return "review|\(pr.id)"
        case .voted(let pr, let by, let vote): return "vote|\(pr.id)|\(by)|\(vote.rawValue)"
        case .pipelineFailed(let run): return "pipeline|\(run.id)|\(run.buildNumber ?? "")"
        case .workItemAssigned(let item): return "workitem|\(item.id)"
        }
    }
}

public enum Changes {
    public static func between(_ previous: Snapshot?, _ current: Snapshot) -> [Change] {
        guard let previous else { return [] }
        var changes: [Change] = []

        if previous.toReview.error == nil, current.toReview.error == nil {
            let known = Set(previous.toReview.items.map(\.id))
            changes += current.toReview.items.filter { !known.contains($0.id) }.map(Change.reviewRequested)
        }

        if previous.mine.error == nil, current.mine.error == nil {
            let before = Dictionary(previous.mine.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for pr in current.mine.items {
                guard let old = before[pr.id] else { continue }
                let oldVotes = Dictionary(old.reviewers.map { ($0.id, $0.vote) }, uniquingKeysWith: { first, _ in first })
                for reviewer in pr.people where reviewer.vote != .none && oldVotes[reviewer.id] != reviewer.vote {
                    changes.append(.voted(pr, by: reviewer.name, reviewer.vote))
                }
            }
        }

        if previous.pipelines.error == nil, current.pipelines.error == nil {
            let before = Dictionary(previous.pipelines.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for run in current.pipelines.items where run.result == .failed {
                guard let old = before[run.id] else { continue }
                if old.result != .failed || old.buildNumber != run.buildNumber {
                    changes.append(.pipelineFailed(run))
                }
            }
        }

        if previous.workItems.error == nil, current.workItems.error == nil {
            let known = Set(previous.workItems.items.map(\.id))
            changes += current.workItems.items.filter { !known.contains($0.id) }.map(Change.workItemAssigned)
        }

        return changes
    }
}
