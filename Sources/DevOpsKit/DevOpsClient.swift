import Foundation

public enum DevOpsError: Error, LocalizedError, Equatable {
    case invalidOrganization
    case missingToken
    case unauthorized
    case http(Int, String)
    case network(String)
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOrganization: return "Enter your organization, e.g. https://dev.azure.com/contoso."
        case .missingToken: return "Add a personal access token in Settings."
        case .unauthorized: return "Azure DevOps rejected the personal access token. It may have expired or lack the required scopes."
        case .http(let code, let message): return message.isEmpty ? "Azure DevOps returned HTTP \(code)." : "Azure DevOps returned HTTP \(code): \(message)"
        case .network(let message): return message
        case .decode(let message): return "Unexpected Azure DevOps response: \(message)"
        }
    }
}

public struct Organization: Sendable, Equatable {
    public let url: URL

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.contains("/") && !trimmed.contains(".") {
            trimmed = "dev.azure.com/" + trimmed
        }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme, scheme == "https" || scheme == "http",
              let host = components.host?.lowercased() else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        let port = components.port.map { ":\($0)" } ?? ""
        let path: String
        if host == "dev.azure.com" {
            guard let first = segments.first else { return nil }
            path = "/" + first
        } else if host.hasSuffix(".visualstudio.com") {
            path = ""
        } else {
            let cut = segments.firstIndex { $0.hasPrefix("_") } ?? segments.endIndex
            path = segments[..<cut].map { "/" + $0 }.joined()
        }
        guard let url = URL(string: "\(scheme)://\(host)\(port)\(path)") else { return nil }
        self.url = url
    }

    public var name: String {
        if url.host == "dev.azure.com" { return url.lastPathComponent }
        if let host = url.host, host.hasSuffix(".visualstudio.com") {
            return String(host.dropLast(".visualstudio.com".count))
        }
        return url.lastPathComponent.isEmpty || url.path.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent
    }
}

public struct Project: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DevOpsClient: Sendable {
    public let organization: Organization
    private let token: String

    static let apiVersion = "7.1"
    static let closedStates = ["Closed", "Done", "Removed", "Resolved", "Completed", "Cut"]
    static let buildPolicyType = "0609b952-1397-4640-95ec-e00a01b2c241"
    static let ciReasons = "individualCI,batchedCI,schedule,manual,resourceTrigger,buildCompletion,triggered"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    public init(organization: Organization, token: String) {
        self.organization = organization
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func connection() async throws -> (id: String, name: String) {
        let data = try await get("_apis/connectionData", version: "7.1-preview")
        let body: ConnectionData = try decode(data)
        guard let user = body.authenticatedUser, let id = user.id, !id.isEmpty else { throw DevOpsError.unauthorized }
        return (id, user.providerDisplayName ?? user.properties?.account?.value ?? "")
    }

    public func pullRequests(reviewer userID: String) async throws -> [PullRequest] {
        try await pullRequests(criteria: "searchCriteria.reviewerId", userID: userID)
            .filter { $0.awaitsReview(from: userID) }
    }

    public func pullRequests(creator userID: String) async throws -> [PullRequest] {
        try await pullRequests(criteria: "searchCriteria.creatorId", userID: userID)
    }

    func pullRequests(criteria: String, userID: String) async throws -> [PullRequest] {
        let data = try await get("_apis/git/pullrequests", query: [
            criteria: userID,
            "searchCriteria.status": "active",
            "$top": "200",
        ])
        let body: ListResponse<PullRequestDTO> = try decode(data)
        return body.value.map { $0.model(organization: organization) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    public func buildCheck(projectID: String, pullRequestID: Int) async throws -> CheckState {
        let artifact = "vstfs:///CodeReview/CodeReviewId/\(projectID)/\(pullRequestID)"
        let data = try await get("\(projectID)/_apis/policy/evaluations", query: ["artifactId": artifact], version: "7.1-preview.1")
        let body: ListResponse<PolicyEvaluationDTO> = try decode(data)
        return Self.buildCheck(body.value)
    }

    static func buildCheck(_ evaluations: [PolicyEvaluationDTO]) -> CheckState {
        let builds = evaluations.filter {
            $0.configuration?.type?.id == buildPolicyType && $0.configuration?.isEnabled != false
        }
        return builds.map { CheckState(policyStatus: $0.status) }.max() ?? .none
    }

    public func projects() async throws -> [Project] {
        let data = try await get("_apis/projects", query: ["$top": "500"])
        let body: ListResponse<ProjectDTO> = try decode(data)
        return body.value.map { Project(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func pipelines(in project: Project) async throws -> [PipelineRef] {
        var refs: [PipelineRef] = []
        var continuation: String?
        repeat {
            var query = ["$top": "1000", "queryOrder": "definitionNameAscending"]
            if let continuation { query["continuationToken"] = continuation }
            let (data, response) = try await send(path: "\(project.id)/_apis/build/definitions", query: query, version: Self.apiVersion)
            let body: ListResponse<DefinitionDTO> = try decode(data)
            refs += body.value.map {
                PipelineRef(projectID: project.id, projectName: project.name, definitionID: $0.id, name: Self.pipelineName(path: $0.path, name: $0.name))
            }
            continuation = response.value(forHTTPHeaderField: "x-ms-continuationtoken")
        } while continuation != nil && refs.count < 10_000
        return refs
    }

    static func pipelineName(path: String?, name: String) -> String {
        let folder = (path ?? "").split(separator: "\\").joined(separator: "/")
        return folder.isEmpty ? name : "\(folder)/\(name)"
    }

    public func statuses(of pipelines: [PipelineRef]) async throws -> [PipelineStatus] {
        let byProject = Dictionary(grouping: pipelines, by: \.projectID)
        return try await withThrowingTaskGroup(of: [PipelineStatus].self) { group in
            for (projectID, refs) in byProject {
                for chunk in stride(from: 0, to: refs.count, by: 50).map({ Array(refs[$0..<min($0 + 50, refs.count)]) }) {
                    group.addTask { try await statuses(projectID: projectID, refs: chunk) }
                }
            }
            var results: [PipelineStatus] = []
            for try await statuses in group { results += statuses }
            let order = Dictionary(pipelines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            return results.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        }
    }

    private func statuses(projectID: String, refs: [PipelineRef]) async throws -> [PipelineStatus] {
        let ids = refs.map { String($0.definitionID) }.joined(separator: ",")
        let latestQuery = [
            "definitions": ids,
            "maxBuildsPerDefinition": "1",
            "reasonFilter": Self.ciReasons,
            "queryOrder": "queueTimeDescending",
        ]
        var completedQuery = latestQuery
        completedQuery["statusFilter"] = "completed"
        completedQuery["queryOrder"] = "finishTimeDescending"
        let path = "\(projectID)/_apis/build/builds"
        let finishedQuery = completedQuery
        async let latestData = get(path, query: latestQuery)
        async let completedData = get(path, query: finishedQuery)
        let latest: ListResponse<BuildDTO> = try decode(try await latestData)
        let completed: ListResponse<BuildDTO> = try decode(try await completedData)
        return Self.merge(refs: refs, latest: latest.value, completed: completed.value)
    }

    static func merge(refs: [PipelineRef], latest: [BuildDTO], completed: [BuildDTO]) -> [PipelineStatus] {
        let latestByID = Dictionary(latest.compactMap { build in build.definition?.id.map { ($0, build) } }, uniquingKeysWith: { first, _ in first })
        let completedByID = Dictionary(completed.compactMap { build in build.definition?.id.map { ($0, build) } }, uniquingKeysWith: { first, _ in first })
        return refs.map { ref in
            let done = completedByID[ref.definitionID]
            let newest = latestByID[ref.definitionID]
            let running = newest.map { $0.status != "completed" } ?? false
            let shown = done ?? newest
            return PipelineStatus(
                pipeline: ref,
                result: RunResult(done?.result),
                isRunning: running,
                buildNumber: shown?.buildNumber,
                branch: shown?.sourceBranch.map(PullRequest.shortBranch),
                requestedBy: shown?.requestedFor?.displayName,
                finishedAt: done?.finishTime.flatMap(DevOpsDate.parse),
                url: shown?.links?.web?.href.flatMap(URL.init(string:))
            )
        }
    }

    public func workItems() async throws -> [WorkItem] {
        let states = Self.closedStates.map { "'\($0)'" }.joined(separator: ", ")
        let wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN (\(states)) ORDER BY [System.ChangedDate] DESC"
        let found: WiqlResponse = try decode(try await post("_apis/wit/wiql", query: ["$top": "50"], body: ["query": wiql]))
        let ids = found.workItems.map(\.id)
        guard !ids.isEmpty else { return [] }
        let fields = ["System.Id", "System.Title", "System.WorkItemType", "System.State", "System.TeamProject", "System.ChangedDate", "Microsoft.VSTS.Common.Priority"]
        let batch: ListResponse<WorkItemDTO> = try decode(try await post("_apis/wit/workitemsbatch", body: WorkItemBatchRequest(ids: ids, fields: fields)))
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return batch.value.map { $0.model(organization: organization) }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    public func snapshot(pipelines: [PipelineRef], now: Date = Date()) async throws -> Snapshot {
        let me = try await connection()
        async let review = section { try await pullRequests(reviewer: me.id) }
        async let mine = section { await withBuildChecks(try await pullRequests(creator: me.id)) }
        async let runs = section { try await pipelines.isEmpty ? [] : statuses(of: pipelines) }
        async let items = section { try await workItems() }
        return Snapshot(
            user: me.name,
            userID: me.id,
            toReview: await review,
            mine: await mine,
            pipelines: await runs,
            workItems: await items,
            fetchedAt: now
        )
    }

    private func withBuildChecks(_ pullRequests: [PullRequest]) async -> [PullRequest] {
        await withTaskGroup(of: (Int, CheckState).self) { group in
            for pr in pullRequests where !pr.projectID.isEmpty {
                group.addTask {
                    (pr.id, (try? await buildCheck(projectID: pr.projectID, pullRequestID: pr.id)) ?? .none)
                }
            }
            var checks: [Int: CheckState] = [:]
            for await (id, state) in group { checks[id] = state }
            return pullRequests.map { pr in
                var copy = pr
                copy.build = checks[pr.id] ?? .none
                return copy
            }
        }
    }

    private func section<Item>(_ load: () async throws -> [Item]) async -> Section<Item> {
        do {
            return Section(items: try await load())
        } catch {
            return Section(error: error.localizedDescription)
        }
    }

    func get(_ path: String, query: [String: String] = [:], version: String = apiVersion) async throws -> Data {
        try await send(path: path, query: query, version: version).0
    }

    func post<Body: Encodable>(_ path: String, query: [String: String] = [:], body: Body) async throws -> Data {
        try await send(path: path, query: query, version: Self.apiVersion, body: try JSONEncoder().encode(body)).0
    }

    func url(_ path: String, query: [String: String], version: String) -> URL? {
        guard var components = URLComponents(url: organization.url.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "api-version", value: version)]
        let encoded = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "/", with: "%2F")
        components.percentEncodedQuery = encoded
        return components.url
    }

    private func send(path: String, query: [String: String], version: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard !token.isEmpty else { throw DevOpsError.missingToken }
        guard let url = url(path, query: query, version: version) else { throw DevOpsError.invalidOrganization }
        var request = URLRequest(url: url)
        request.setValue("Basic " + Data(":\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "X-TFS-FedAuthRedirect-Suppress")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw DevOpsError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw DevOpsError.network("No response from Azure DevOps.") }
        let isJSON = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json")
        switch http.statusCode {
        case 401, 203:
            throw DevOpsError.unauthorized
        case 200..<300 where isJSON:
            return (data, http)
        case 200..<400:
            throw DevOpsError.unauthorized
        default:
            throw DevOpsError.http(http.statusCode, Self.message(from: data))
        }
    }

    static func message(from data: Data) -> String {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message, !message.isEmpty else { return "" }
        return message.count > 200 ? String(message.prefix(200)) + "…" : message
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DevOpsError.decode(error.localizedDescription)
        }
    }
}

public enum DevOpsDate {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."), let end = trimmed[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            trimmed.removeSubrange(dot..<end)
        }
        return formatter.date(from: trimmed)
    }
}

struct ListResponse<Item: Decodable>: Decodable {
    let value: [Item]
}

struct ErrorBody: Decodable {
    let message: String?
}

struct ConnectionData: Decodable {
    struct User: Decodable {
        struct Properties: Decodable {
            struct Value: Decodable {
                let value: String?

                enum CodingKeys: String, CodingKey {
                    case value = "$value"
                }
            }

            let account: Value?

            enum CodingKeys: String, CodingKey {
                case account = "Account"
            }
        }

        let id: String?
        let providerDisplayName: String?
        let properties: Properties?
    }

    let authenticatedUser: User?
}

struct IdentityDTO: Decodable {
    let id: String?
    let displayName: String?
}

struct PullRequestDTO: Decodable {
    struct Repository: Decodable {
        struct Project: Decodable {
            let id: String?
            let name: String?
        }

        let name: String?
        let project: Project?
    }

    struct ReviewerDTO: Decodable {
        let id: String?
        let displayName: String?
        let vote: Int?
        let isRequired: Bool?
        let isContainer: Bool?
        let hasDeclined: Bool?
    }

    let pullRequestId: Int
    let title: String?
    let repository: Repository?
    let createdBy: IdentityDTO?
    let creationDate: String?
    let isDraft: Bool?
    let mergeStatus: String?
    let sourceRefName: String?
    let targetRefName: String?
    let reviewers: [ReviewerDTO]?

    func model(organization: Organization) -> PullRequest {
        let project = repository?.project?.name ?? ""
        let repo = repository?.name ?? ""
        let url = project.isEmpty || repo.isEmpty ? nil : organization.url
            .appendingPathComponent(project)
            .appendingPathComponent("_git")
            .appendingPathComponent(repo)
            .appendingPathComponent("pullrequest")
            .appendingPathComponent(String(pullRequestId))
        return PullRequest(
            id: pullRequestId,
            title: title ?? "Pull request \(pullRequestId)",
            project: project,
            projectID: repository?.project?.id ?? "",
            repository: repo,
            author: createdBy?.displayName ?? "",
            authorID: createdBy?.id ?? "",
            createdAt: creationDate.flatMap(DevOpsDate.parse),
            isDraft: isDraft ?? false,
            hasConflicts: mergeStatus == "conflicts",
            sourceBranch: sourceRefName ?? "",
            targetBranch: targetRefName ?? "",
            reviewers: (reviewers ?? []).map {
                Reviewer(
                    id: $0.id ?? "",
                    name: $0.displayName ?? "",
                    vote: Vote(score: $0.vote ?? 0),
                    isRequired: $0.isRequired ?? false,
                    isGroup: $0.isContainer ?? false,
                    hasDeclined: $0.hasDeclined ?? false
                )
            },
            url: url
        )
    }
}

struct PolicyEvaluationDTO: Decodable {
    struct Configuration: Decodable {
        struct PolicyType: Decodable {
            let id: String?
        }

        let isEnabled: Bool?
        let isBlocking: Bool?
        let type: PolicyType?
    }

    let status: String?
    let configuration: Configuration?
}

struct ProjectDTO: Decodable {
    let id: String
    let name: String
}

struct DefinitionDTO: Decodable {
    let id: Int
    let name: String
    let path: String?
}

struct BuildDTO: Decodable {
    struct Definition: Decodable {
        let id: Int?
    }

    struct Links: Decodable {
        struct Link: Decodable {
            let href: String?
        }

        let web: Link?
    }

    let buildNumber: String?
    let status: String?
    let result: String?
    let sourceBranch: String?
    let finishTime: String?
    let definition: Definition?
    let requestedFor: IdentityDTO?
    let links: Links?

    enum CodingKeys: String, CodingKey {
        case buildNumber, status, result, sourceBranch, finishTime, definition, requestedFor
        case links = "_links"
    }
}

struct WiqlResponse: Decodable {
    struct Reference: Decodable {
        let id: Int
    }

    let workItems: [Reference]
}

struct WorkItemBatchRequest: Encodable {
    let ids: [Int]
    let fields: [String]
}

struct WorkItemDTO: Decodable {
    struct Fields: Decodable {
        let title: String?
        let type: String?
        let state: String?
        let project: String?
        let changed: String?
        let priority: Int?

        enum CodingKeys: String, CodingKey {
            case title = "System.Title"
            case type = "System.WorkItemType"
            case state = "System.State"
            case project = "System.TeamProject"
            case changed = "System.ChangedDate"
            case priority = "Microsoft.VSTS.Common.Priority"
        }
    }

    let id: Int
    let fields: Fields

    func model(organization: Organization) -> WorkItem {
        let project = fields.project ?? ""
        let url = project.isEmpty ? nil : organization.url
            .appendingPathComponent(project)
            .appendingPathComponent("_workitems")
            .appendingPathComponent("edit")
            .appendingPathComponent(String(id))
        return WorkItem(
            id: id,
            title: fields.title ?? "Work item \(id)",
            type: fields.type ?? "",
            state: fields.state ?? "",
            project: project,
            priority: fields.priority,
            changedAt: fields.changed.flatMap(DevOpsDate.parse),
            url: url
        )
    }
}
