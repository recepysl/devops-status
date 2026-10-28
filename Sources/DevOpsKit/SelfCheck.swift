import Foundation

public enum SelfCheck {
    public static func run() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { failures.append(message()) }
        }

        let organizations: [(String, String?)] = [
            ("contoso", "https://dev.azure.com/contoso"),
            ("dev.azure.com/contoso/", "https://dev.azure.com/contoso"),
            ("https://dev.azure.com/contoso/Web%20Shop/_git/api/pullrequest/12", "https://dev.azure.com/contoso"),
            ("https://contoso.visualstudio.com/Web/_git/api", "https://contoso.visualstudio.com"),
            ("https://tfs.example.com:8443/tfs/DefaultCollection/_apis", "https://tfs.example.com:8443/tfs/DefaultCollection"),
            ("", nil),
            ("not a url", nil),
            ("ftp://dev.azure.com/contoso", nil),
        ]
        for (input, expected) in organizations {
            let actual = Organization(input)?.url.absoluteString
            expect(actual == expected, "organization \"\(input)\" → \(actual ?? "nil"), expected \(expected ?? "nil")")
        }
        expect(Organization("contoso")?.name == "contoso", "organization name")
        expect(Organization("https://contoso.visualstudio.com")?.name == "contoso", "legacy organization name")

        let date = DevOpsDate.parse("2026-10-27T08:12:33.1234567Z")
        expect(date == DevOpsDate.parse("2026-10-27T08:12:33Z") && date != nil, "seven-digit fractional seconds parse")
        expect(DevOpsDate.parse("2026-10-27T08:12:33.12Z") != nil, "two-digit fractional seconds parse")
        expect(DevOpsDate.parse("yesterday") == nil, "garbage date is nil")

        expect(Vote(score: 10) == .approved && Vote(score: 5) == .approvedWithSuggestions && Vote(score: -5) == .waitingForAuthor, "vote mapping")
        expect(Vote(score: 7) == .approved && Vote(score: -3) == .rejected, "unknown votes fall back by sign")

        let organization = Organization("contoso")!
        do {
            let prs = try JSONDecoder().decode(ListResponse<PullRequestDTO>.self, from: samplePullRequests)
                .value.map { $0.model(organization: organization) }
            let byID = Dictionary(uniqueKeysWithValues: prs.map { ($0.id, $0) })
            let first = byID[101]
            expect(first?.url?.absoluteString == "https://dev.azure.com/contoso/Web%20Shop/_git/checkout-api/pullrequest/101", "pull request web URL, got \(String(describing: first?.url))")
            expect(first?.shortTargetBranch == "main", "target branch shortened")
            expect(first?.awaitsReview(from: me) == true, "pending vote awaits review")
            expect(first?.author == "Ada Lovelace", "author name")
            expect(byID[102]?.awaitsReview(from: me) == false, "already voted is not pending")
            expect(byID[103]?.awaitsReview(from: me) == false, "drafts are not pending")
            expect(byID[104]?.awaitsReview(from: me) == false, "declined reviews are not pending")
            expect(byID[105]?.awaitsReview(from: me) == false, "own pull request is not pending")

            expect(byID[102]?.reviewState == .approved, "approval by a person, got \(String(describing: byID[102]?.reviewState))")
            expect(byID[105]?.reviewState == .waitingForAuthor, "waiting for author state")
            expect(byID[105]?.severity == .attention, "waiting for author is attention")
            expect(byID[106]?.hasConflicts == true && byID[106]?.severity == .critical, "merge conflicts are critical")
            expect(byID[107]?.reviewState == .pending, "required reviewer without vote keeps it pending")
            expect(byID[108]?.reviewState == .rejected && byID[108]?.severity == .critical, "rejection is critical")
            expect(byID[102]?.approvals == 1, "group votes are not counted as approvals")

            var failing = byID[102]!
            failing.build = .failed
            expect(failing.severity == .critical, "failed build is critical")
        } catch {
            failures.append("decoding sample pull requests threw: \(error)")
        }

        do {
            let evaluations = try JSONDecoder().decode(ListResponse<PolicyEvaluationDTO>.self, from: samplePolicies).value
            expect(DevOpsClient.buildCheck(evaluations) == .failed, "worst build policy wins, got \(DevOpsClient.buildCheck(evaluations))")
            expect(DevOpsClient.buildCheck(Array(evaluations.prefix(2))) == .passed, "non-build policies ignored")
            expect(DevOpsClient.buildCheck([]) == .none, "no build policy")
        } catch {
            failures.append("decoding sample policies threw: \(error)")
        }

        let refs = [
            PipelineRef(projectID: "p", projectName: "Web", definitionID: 1, name: "api-ci"),
            PipelineRef(projectID: "p", projectName: "Web", definitionID: 2, name: "web-ci"),
            PipelineRef(projectID: "p", projectName: "Web", definitionID: 3, name: "nightly"),
            PipelineRef(projectID: "p", projectName: "Web", definitionID: 4, name: "never-run"),
        ]
        do {
            let latest = try JSONDecoder().decode(ListResponse<BuildDTO>.self, from: sampleLatestBuilds).value
            let completed = try JSONDecoder().decode(ListResponse<BuildDTO>.self, from: sampleCompletedBuilds).value
            let statuses = Dictionary(uniqueKeysWithValues: DevOpsClient.merge(refs: refs, latest: latest, completed: completed).map { ($0.pipeline.definitionID, $0) })
            expect(statuses[1]?.result == .failed && statuses[1]?.isRunning == false, "failed pipeline")
            expect(statuses[1]?.severity == .critical, "failed pipeline is critical")
            expect(statuses[1]?.branch == "main", "branch shortened")
            expect(statuses[1]?.url?.absoluteString == "https://dev.azure.com/contoso/p/_build/results?buildId=9001", "build web link")
            expect(statuses[2]?.result == .succeeded && statuses[2]?.isRunning == true, "running pipeline keeps last result")
            expect(statuses[3]?.result == .partiallySucceeded && statuses[3]?.severity == .attention, "partial success is attention")
            expect(statuses[4]?.result == RunResult.none && statuses[4]?.severity == .ok, "pipeline without runs")
        } catch {
            failures.append("decoding sample builds threw: \(error)")
        }
        expect(DevOpsClient.pipelineName(path: "\\", name: "api-ci") == "api-ci", "root pipeline name")
        expect(DevOpsClient.pipelineName(path: "\\Services\\Payments", name: "api-ci") == "Services/Payments/api-ci", "folder pipeline name")

        do {
            let items = try JSONDecoder().decode(ListResponse<WorkItemDTO>.self, from: sampleWorkItems).value.map { $0.model(organization: organization) }
            expect(items.count == 2, "work item count")
            expect(items.first?.type == "Bug" && items.first?.priority == 1, "work item fields")
            expect(items.first?.url?.absoluteString == "https://dev.azure.com/contoso/Web%20Shop/_workitems/edit/4711", "work item URL, got \(String(describing: items.first?.url))")
        } catch {
            failures.append("decoding sample work items threw: \(error)")
        }

        do {
            let connection = try JSONDecoder().decode(ConnectionData.self, from: Data(#"{"authenticatedUser":{"id":"me-id","providerDisplayName":"Grace Hopper","properties":{"Account":{"$type":"System.String","$value":"grace@example.com"}}}}"#.utf8))
            expect(connection.authenticatedUser?.id == "me-id" && connection.authenticatedUser?.properties?.account?.value == "grace@example.com", "connection data")
        } catch {
            failures.append("decoding connection data threw: \(error)")
        }

        failures += changeChecks()

        let client = DevOpsClient(organization: organization, token: "x")
        let artifactURL = client.url("p/_apis/policy/evaluations", query: ["artifactId": "vstfs:///CodeReview/CodeReviewId/p/1"], version: "7.1")?.absoluteString ?? ""
        expect(artifactURL.contains("artifactId=vstfs%3A%2F%2F%2FCodeReview%2FCodeReviewId%2Fp%2F1"), "artifact id is fully encoded, got \(artifactURL)")
        expect(artifactURL.hasSuffix("api-version=7.1"), "api version appended")

        return failures
    }

    static func changeChecks() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { failures.append(message()) }
        }

        let ref = PipelineRef(projectID: "p", projectName: "Web", definitionID: 1, name: "api-ci")
        func pr(_ id: Int, votes: [(String, Int)] = []) -> PullRequest {
            PullRequest(id: id, title: "PR \(id)", project: "Web", repository: "api", author: "Me", authorID: me,
                        reviewers: votes.map { Reviewer(id: $0.0, name: $0.0, vote: Vote(score: $0.1)) })
        }
        let before = Snapshot(
            toReview: .init(items: [pr(1)]),
            mine: .init(items: [pr(10, votes: [("ada", 0), ("alan", 10)])]),
            pipelines: .init(items: [PipelineStatus(pipeline: ref, result: .succeeded, buildNumber: "41")]),
            workItems: .init(items: [WorkItem(id: 7, title: "Old", type: "Task", state: "Active", project: "Web")])
        )
        let after = Snapshot(
            toReview: .init(items: [pr(1), pr(2)]),
            mine: .init(items: [pr(10, votes: [("ada", 10), ("alan", 10)]), pr(11, votes: [("ada", -10)])]),
            pipelines: .init(items: [PipelineStatus(pipeline: ref, result: .failed, buildNumber: "42")]),
            workItems: .init(items: [WorkItem(id: 7, title: "Old", type: "Task", state: "Active", project: "Web"), WorkItem(id: 8, title: "New", type: "Bug", state: "New", project: "Web")])
        )
        let keys = Set(Changes.between(before, after).map(\.key))
        expect(keys == ["review|2", "vote|10|ada|10", "pipeline|p/1|42", "workitem|8"], "changes detected: \(keys.sorted())")
        expect(Changes.between(nil, after).isEmpty, "no changes on the first snapshot")
        expect(Changes.between(after, after).isEmpty, "no repeats")

        var broken = after
        broken.toReview = .init(error: "offline")
        expect(Changes.between(broken, after).filter { $0.key.hasPrefix("review") }.isEmpty, "recovering from an error does not re-announce reviews")

        let failedAgain = Snapshot(pipelines: .init(items: [PipelineStatus(pipeline: ref, result: .failed, buildNumber: "43")]))
        expect(Changes.between(after, failedAgain).map(\.key) == ["pipeline|p/1|43"], "a new failing run is announced again")

        expect(after.badgeCount == 3, "badge counts reviews and failed pipelines, got \(after.badgeCount)")
        expect(after.severity == .critical, "failed pipeline makes the snapshot critical")
        expect(Snapshot(toReview: .init(items: [pr(1)])).severity == .attention, "pending reviews are attention")
        expect(Snapshot().severity == .ok, "empty snapshot is ok")
        return failures
    }

    static let me = "11111111-0000-0000-0000-000000000001"

    static let samplePullRequests = Data("""
    { "count": 8, "value": [
      { "pullRequestId": 101, "title": "Add retry to payment client", "isDraft": false, "mergeStatus": "succeeded",
        "creationDate": "2026-10-27T08:12:33.1234567Z", "sourceRefName": "refs/heads/feature/retry", "targetRefName": "refs/heads/main",
        "repository": { "name": "checkout-api", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "ada", "displayName": "Ada Lovelace" },
        "reviewers": [ { "id": "\(me)", "displayName": "Me", "vote": 0, "isRequired": true } ] },
      { "pullRequestId": 102, "title": "Bump dependencies", "mergeStatus": "succeeded",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "alan", "displayName": "Alan Turing" },
        "reviewers": [ { "id": "\(me)", "displayName": "Me", "vote": 10 },
                       { "id": "team", "displayName": "[Web]\\\\Reviewers", "vote": 10, "isContainer": true } ] },
      { "pullRequestId": 103, "title": "WIP", "isDraft": true,
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "alan", "displayName": "Alan Turing" },
        "reviewers": [ { "id": "\(me)", "displayName": "Me", "vote": 0 } ] },
      { "pullRequestId": 104, "title": "Declined",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "alan", "displayName": "Alan Turing" },
        "reviewers": [ { "id": "\(me)", "displayName": "Me", "vote": 0, "hasDeclined": true } ] },
      { "pullRequestId": 105, "title": "Mine",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "\(me)", "displayName": "Me" },
        "reviewers": [ { "id": "\(me)", "displayName": "Me", "vote": 0 }, { "id": "ada", "displayName": "Ada Lovelace", "vote": -5 } ] },
      { "pullRequestId": 106, "title": "Conflicting", "mergeStatus": "conflicts",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "\(me)", "displayName": "Me" }, "reviewers": [] },
      { "pullRequestId": 107, "title": "Required reviewer",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "\(me)", "displayName": "Me" },
        "reviewers": [ { "id": "ada", "displayName": "Ada Lovelace", "vote": 10 }, { "id": "alan", "displayName": "Alan Turing", "vote": 0, "isRequired": true } ] },
      { "pullRequestId": 108, "title": "Rejected",
        "repository": { "name": "web", "project": { "id": "p1", "name": "Web Shop" } },
        "createdBy": { "id": "\(me)", "displayName": "Me" },
        "reviewers": [ { "id": "ada", "displayName": "Ada Lovelace", "vote": -10 } ] }
    ] }
    """.utf8)

    static let samplePolicies = Data("""
    { "count": 4, "value": [
      { "status": "approved", "configuration": { "isEnabled": true, "type": { "id": "fa4e907d-c16b-4a4c-9dfa-4906e5d171dd" } } },
      { "status": "approved", "configuration": { "isEnabled": true, "type": { "id": "0609b952-1397-4640-95ec-e00a01b2c241" } } },
      { "status": "rejected", "configuration": { "isEnabled": true, "type": { "id": "0609b952-1397-4640-95ec-e00a01b2c241" } } },
      { "status": "rejected", "configuration": { "isEnabled": false, "type": { "id": "0609b952-1397-4640-95ec-e00a01b2c241" } } }
    ] }
    """.utf8)

    static let sampleLatestBuilds = Data("""
    { "count": 3, "value": [
      { "buildNumber": "20261027.4", "status": "completed", "result": "failed", "sourceBranch": "refs/heads/main",
        "finishTime": "2026-10-27T09:00:00.52Z", "definition": { "id": 1 }, "requestedFor": { "displayName": "Ada Lovelace" },
        "_links": { "web": { "href": "https://dev.azure.com/contoso/p/_build/results?buildId=9001" } } },
      { "buildNumber": "20261027.9", "status": "inProgress", "sourceBranch": "refs/heads/main", "definition": { "id": 2 } },
      { "buildNumber": "20261027.1", "status": "completed", "result": "partiallySucceeded", "definition": { "id": 3 } }
    ] }
    """.utf8)

    static let sampleCompletedBuilds = Data("""
    { "count": 3, "value": [
      { "buildNumber": "20261027.4", "status": "completed", "result": "failed", "sourceBranch": "refs/heads/main",
        "finishTime": "2026-10-27T09:00:00.52Z", "definition": { "id": 1 },
        "_links": { "web": { "href": "https://dev.azure.com/contoso/p/_build/results?buildId=9001" } } },
      { "buildNumber": "20261027.8", "status": "completed", "result": "succeeded", "definition": { "id": 2 } },
      { "buildNumber": "20261027.1", "status": "completed", "result": "partiallySucceeded", "definition": { "id": 3 } }
    ] }
    """.utf8)

    static let sampleWorkItems = Data("""
    { "count": 2, "value": [
      { "id": 4711, "fields": { "System.Id": 4711, "System.Title": "Checkout fails for saved cards", "System.WorkItemType": "Bug",
        "System.State": "Active", "System.TeamProject": "Web Shop", "System.ChangedDate": "2026-10-27T07:00:00.1Z",
        "Microsoft.VSTS.Common.Priority": 1 } },
      { "id": 4712, "fields": { "System.Title": "Document retries", "System.WorkItemType": "Task", "System.State": "New", "System.TeamProject": "Web Shop" } }
    ] }
    """.utf8)
}
