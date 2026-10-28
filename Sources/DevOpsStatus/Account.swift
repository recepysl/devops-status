import Foundation
import Security
import DevOpsKit

@MainActor
final class Account: ObservableObject {
    static let shared = Account(preferences: .shared)

    @Published var newOrganization = ""
    @Published var newToken = ""
    @Published private(set) var formError: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var userName: String?

    private let preferences: Preferences
    private let persistent: Bool

    init(preferences: Preferences, persistent: Bool = true, previewUser: String? = nil) {
        self.preferences = preferences
        self.persistent = persistent
        self.userName = previewUser
    }

    var organization: Organization? {
        Organization(preferences.organization)
    }

    var isConnected: Bool {
        organization != nil && (!persistent || token != nil)
    }

    var token: String? {
        guard persistent, let organization else { return nil }
        return Keychain.get(account: organization.url.absoluteString)
    }

    func client() -> DevOpsClient? {
        guard let organization, let token else { return nil }
        return DevOpsClient(organization: organization, token: token)
    }

    func didLoad(user: String) {
        userName = user
    }

    func connect() async {
        guard let organization = Organization(newOrganization) else {
            formError = DevOpsError.invalidOrganization.localizedDescription
            return
        }
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            formError = DevOpsError.missingToken.localizedDescription
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let me = try await DevOpsClient(organization: organization, token: token).connection()
            try Keychain.set(token, account: organization.url.absoluteString)
            preferences.organization = organization.url.absoluteString
            userName = me.name
            newOrganization = ""
            newToken = ""
            formError = nil
            StatusMonitor.shared.refreshNow()
        } catch {
            formError = error.localizedDescription
        }
    }

    func disconnect() {
        if let organization {
            Keychain.delete(account: organization.url.absoluteString)
        }
        preferences.organization = ""
        preferences.pipelines = []
        userName = nil
        StatusMonitor.shared.reset()
    }
}

enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "io.github.recepysl.devops-status") + ".pat"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "DevOps Status — Azure DevOps personal access token"
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func get(account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Couldn't save the token to the Keychain: \(message)"
        }
    }
}
