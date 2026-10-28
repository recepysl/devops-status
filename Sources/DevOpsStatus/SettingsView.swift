import SwiftUI
import AppKit
import DevOpsKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(
                preferences: .shared, account: .shared, picker: PipelinePicker(account: .shared), login: .shared
            ))
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "DevOps Status Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class PipelinePicker: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var projectID: String? {
        didSet { if projectID != oldValue { Task { await loadPipelines() } } }
    }
    @Published private(set) var pipelines: [String: [PipelineRef]] = [:]
    @Published var search = ""
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let account: Account

    init(account: Account, preview projects: [Project] = [], pipelines: [String: [PipelineRef]] = [:]) {
        self.account = account
        self.projects = projects
        self.pipelines = pipelines
        self.projectID = projects.first?.id
    }

    var visible: [PipelineRef] {
        guard let projectID else { return [] }
        let all = pipelines[projectID] ?? []
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func loadProjects() async {
        guard projects.isEmpty, let client = account.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await client.projects()
            error = nil
            if projectID == nil { projectID = projects.first?.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadPipelines() async {
        guard let projectID, pipelines[projectID] == nil,
              let project = projects.first(where: { $0.id == projectID }),
              let client = account.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            pipelines[projectID] = try await client.pipelines(in: project)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var account: Account
    @ObservedObject var picker: PipelinePicker
    @ObservedObject var login: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Azure DevOps") {
                if account.isConnected, let organization = account.organization {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(organization.url.absoluteString)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Text(account.userName.map { "Signed in as \($0)" } ?? "Personal access token in the Keychain")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") { account.disconnect() }
                    }
                } else {
                    HStack {
                        TextField("https://dev.azure.com/contoso", text: $account.newOrganization)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        SecureField("Personal access token", text: $account.newToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 180)
                        Button(account.isConnecting ? "Checking…" : "Connect") {
                            Task { await account.connect() }
                        }
                        .disabled(account.isConnecting || account.newOrganization.isEmpty || account.newToken.isEmpty)
                    }
                    if let error = account.formError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Create a token under User settings → Personal access tokens with read access to **Code**, **Build**, **Work Items** and **Project and Team**. It is stored in your Keychain and only sent to your organization.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if account.isConnected {
                section("Pipelines") {
                    pipelineChooser
                }
            }

            section("General") {
                Picker("Refresh every", selection: $preferences.interval) {
                    ForEach(Preferences.intervals, id: \.self) { Text(Format.interval($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Toggle("Notify about review requests, votes, failed pipelines and new work items", isOn: $preferences.notificationsEnabled)
                    .toggleStyle(.checkbox)
                Toggle("Open at Login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                if let error = login.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .task(id: account.isConnected) {
            if account.isConnected { await picker.loadProjects() }
        }
    }

    @ViewBuilder
    private var pipelineChooser: some View {
        HStack {
            Picker("Project", selection: $picker.projectID) {
                ForEach(picker.projects) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
            TextField("Filter", text: $picker.search)
                .textFieldStyle(.roundedBorder)
            if picker.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        if let error = picker.error {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(picker.visible) { pipeline in
                    Toggle(isOn: Binding(
                        get: { preferences.isWatching(pipeline) },
                        set: { preferences.setWatching(pipeline, $0) }
                    )) {
                        Text(pipeline.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                }
                if picker.visible.isEmpty && !picker.isLoading {
                    Text(picker.projectID == nil ? "No projects found." : "No pipelines match.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
        Text(watchingSummary)
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var watchingSummary: String {
        let count = preferences.pipelines.count
        guard count > 0 else { return "Pick the pipelines whose latest CI run you want to see. Pull request builds are ignored." }
        let names = preferences.pipelines.prefix(4).map(\.name).joined(separator: ", ")
        return "Watching \(count): \(names)\(count > 4 ? ", …" : ""). Pull request builds are ignored."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
