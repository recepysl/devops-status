import AppKit
import UserNotifications
import DevOpsKit

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ changes: [Change]) {
        guard let center else { return }
        for change in changes.prefix(5) {
            let content = UNMutableNotificationContent()
            let link: URL?
            switch change {
            case .reviewRequested(let pr):
                content.title = "Review requested"
                content.body = "\(pr.author): \(pr.title)\n\(pr.repository) → \(pr.shortTargetBranch)"
                link = pr.url
            case .voted(let pr, let by, let vote):
                content.title = "\(by): \(vote.label)"
                content.body = pr.title
                link = pr.url
            case .pipelineFailed(let run):
                content.title = "\(run.pipeline.name) failed"
                content.body = [run.buildNumber, run.branch, run.requestedBy].compactMap { $0 }.joined(separator: " · ")
                link = run.url
            case .workItemAssigned(let item):
                content.title = "\(item.type) assigned to you"
                content.body = "#\(item.id) \(item.title)"
                link = item.url
            }
            if let link { content.userInfo = ["url": link.absoluteString] }
            content.sound = .default
            center.add(UNNotificationRequest(identifier: change.key, content: content, trigger: nil))
        }
        if changes.count > 5 {
            let content = UNMutableNotificationContent()
            content.title = "\(changes.count - 5) more updates"
            content.body = "Open DevOps Status in the menu bar to see them."
            center.add(UNNotificationRequest(identifier: "more|\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: link) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
