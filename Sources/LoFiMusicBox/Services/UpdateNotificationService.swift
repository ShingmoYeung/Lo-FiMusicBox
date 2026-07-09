import AppKit
import Foundation
import UserNotifications

/// 封装「发现新版本」的系统通知：请求权限、投递横幅、点击打开 Releases。
/// 仅用于后台检查结果；手动检查仍走 NSAlert，避免重复打扰。
@MainActor
final class UpdateNotificationService: NSObject {
    static let shared = UpdateNotificationService()

    private var didConfigureDelegate = false
    private var authorizationRequested = false

    func prepareIfNeeded() {
        guard !didConfigureDelegate else { return }
        didConfigureDelegate = true
        UNUserNotificationCenter.current().delegate = self
    }

    /// 请求通知权限（可重复调用；系统只会真正弹一次授权框）。
    func requestAuthorizationIfNeeded() async {
        prepareIfNeeded()
        guard !authorizationRequested else { return }
        authorizationRequested = true
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            // 拒绝或失败时静默：后台有更新可回退到关于页状态 / 暂停后弹窗。
        }
    }

    func postUpdateAvailable(release: GitHubLatestRelease) async {
        prepareIfNeeded()
        await requestAuthorizationIfNeeded()

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = LocalizedStrings.text("update.notification.available.title")
        content.body = LocalizedStrings.text(
            "update.notification.available.body",
            release.marketingVersion,
            AppVersion.marketingVersion
        )
        content.sound = .default
        content.userInfo = [
            AppConstants.UpdateCheck.notificationUserInfoReleaseURLKey: release.htmlURL.absoluteString,
            AppConstants.UpdateCheck.notificationUserInfoVersionKey: release.marketingVersion
        ]
        content.categoryIdentifier = AppConstants.UpdateCheck.notificationCategoryIdentifier

        let identifier =
            AppConstants.UpdateCheck.notificationRequestIdentifierPrefix + release.marketingVersion
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // 投递失败不阻断检查流程。
        }
    }
}

extension UpdateNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // App 在前台也显示横幅，避免用户错过后台检查结果。
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let urlString = userInfo[AppConstants.UpdateCheck.notificationUserInfoReleaseURLKey] as? String
        await MainActor.run {
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else if let fallback = URL(string: AppConstants.UpdateCheck.latestReleasePageURL) {
                NSWorkspace.shared.open(fallback)
            }
        }
    }
}
