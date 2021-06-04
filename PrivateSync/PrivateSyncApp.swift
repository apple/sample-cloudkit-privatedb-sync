//
//  PrivateSyncApp.swift
//  (cloudkit-samples) Private Sync
//

import SwiftUI
import UIKit
import CloudKit

@main
struct PrivateSyncApp: App {
    /// We use an AppDelegate class to handle push notification registration and handling.
    @UIApplicationDelegateAdaptor(PrivateSyncAppDelegate.self) private var appDelegate

    /// For simplicity, we'll keep our single ViewModel as a static object to provide access in our app delegate.
    static let vm = ViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(PrivateSyncApp.vm)
        }
    }
}

final class PrivateSyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        debugPrint("Did register for remote notifications")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        debugPrint("ERROR: Failed to register for notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let zoneNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKRecordZoneNotification else {
            completionHandler(.noData)
            return
        }

        debugPrint("Received zone notification: \(zoneNotification)")

        async {
            do {
                try await PrivateSyncApp.vm.fetchLatestChanges()
                completionHandler(.newData)
            } catch {
                debugPrint("Error in fetchLatestChanges: \(error)")
                completionHandler(.failed)
            }
        }
    }
}
