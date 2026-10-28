import Foundation
import DevOpsKit

@MainActor
enum OnceMode {
    static func run() -> Never {
        Task { @MainActor in
            await report()
        }
        RunLoop.main.run()
        exit(2)
    }

    private static func report() async -> Never {
        let arguments = CommandLine.arguments
        let environment = ProcessInfo.processInfo.environment
        let client: DevOpsClient
        if let organization = value(after: "--org", in: arguments).flatMap(Organization.init),
           let token = environment["AZURE_DEVOPS_EXT_PAT"], !token.isEmpty {
            client = DevOpsClient(organization: organization, token: token)
        } else if let saved = Account.shared.client() {
            client = saved
        } else {
            fail("Not connected. Connect in Settings, or pass --org <url> with AZURE_DEVOPS_EXT_PAT set.")
        }

        var pipelines = Preferences.shared.pipelines
        let requested = values(after: "--pipeline", in: arguments)
        if !requested.isEmpty {
            do {
                pipelines = try await resolve(requested, client: client)
            } catch {
                fail(error.localizedDescription)
            }
        }

        let snapshot: Snapshot
        do {
            snapshot = try await client.snapshot(pipelines: pipelines)
        } catch {
            fail(error.localizedDescription)
        }

        print("\(snapshot.user) · \(client.organization.url.absoluteString)")
        print("\nTo review (\(snapshot.toReview.items.count))")
        printSection(snapshot.toReview) { "  • \($0.title)  [\($0.repository) → \($0.shortTargetBranch)] by \($0.author)" }
        print("\nMy pull requests (\(snapshot.mine.items.count))")
        printSection(snapshot.mine) { pr in
            var flags = [pr.reviewState.label]
            if !pr.people.isEmpty { flags.append("\(pr.approvals)/\(pr.people.count) approved") }
            if pr.hasConflicts { flags.append("conflicts") }
            if let build = pr.build.label { flags.append(build.lowercased()) }
            return "  \(mark(pr.severity)) \(pr.title)  [\(pr.repository)] \(flags.joined(separator: ", "))"
        }
        print("\nPipelines (\(snapshot.pipelines.items.count))")
        printSection(snapshot.pipelines) { run in
            let running = run.isRunning ? " (running)" : ""
            return "  \(mark(run.severity)) \(run.pipeline.projectName)/\(run.pipeline.name)  \(run.result.label)\(running)  \(run.buildNumber ?? "")"
        }
        print("\nWork items (\(snapshot.workItems.items.count))")
        printSection(snapshot.workItems) { "  • \($0.type) #\($0.id) \($0.title)  [\($0.state)]" }

        exit(snapshot.hasErrors ? 2 : snapshot.severity == .critical ? 1 : 0)
    }

    private static func resolve(_ requested: [String], client: DevOpsClient) async throws -> [PipelineRef] {
        let projects = try await client.projects()
        var refs: [PipelineRef] = []
        for item in requested {
            let parts = item.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let project = projects.first(where: { $0.name.caseInsensitiveCompare(parts[0]) == .orderedSame || $0.id == parts[0] }) else {
                fail("Unknown pipeline \(item). Use <project>/<definition id or name>.")
            }
            let available = try await client.pipelines(in: project)
            guard let match = available.first(where: { String($0.definitionID) == parts[1] || $0.name.caseInsensitiveCompare(parts[1]) == .orderedSame }) else {
                fail("No pipeline \(parts[1]) in \(project.name).")
            }
            refs.append(match)
        }
        return refs
    }

    private static func printSection<Item>(_ section: Section<Item>, line: (Item) -> String) {
        if let error = section.error {
            print("  ⚠ \(error)")
            return
        }
        for item in section.items { print(line(item)) }
    }

    private static func mark(_ severity: Severity) -> String {
        switch severity {
        case .ok: return "✓"
        case .attention: return "!"
        case .critical: return "✗"
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        values(after: flag, in: arguments).first
    }

    private static func values(after flag: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            arguments[index] == flag && arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(2)
    }
}
