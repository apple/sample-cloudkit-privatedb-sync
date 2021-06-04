# CloudKit Samples: Private Sync with Subscriptions and Push

### Goals

This project demonstrates using CloudKit Database Subscriptions and push notifications to keep two separate instances of an app in sync. Ideally it is run on both a simulator and a real device, and content changes made on the simulator are received and reflected on the device via CloudKit Subscriptions, similar to the functionality of the Notes or Photos apps.

### Prerequisites

* A Mac with [Xcode 12](https://developer.apple.com/xcode/) (or later) installed is required to build and test this project.
* An iOS device which will receive CloudKit change notifications is required to install and run the app on.
* An active [Apple Developer Program membership](https://developer.apple.com/support/compare-memberships/) is needed to create a CloudKit container and sign the app to run on a device.

**Note**: Simulators cannot register for remote push notifications. Running this sample on a device is **required** to receive `CKSubscription` push notifications and observe syncing functionality.

### Setup Instructions

1. Ensure you are logged into your developer account in Xcode with an active membership.
1. In the “Signing & Capabilities” tab of the PrivateSync target, ensure your team is selected in the Signing section, and there is a valid container selected under the “iCloud” section.
1. Ensure that both the simulator you wish to use and the device you will run the app on are logged into the same iCloud account.

#### Using Your Own iCloud Container

* Create a new iCloud container through Xcode’s “Signing & Capabilities” tab of the PrivateSync app target.
* Update the `containerIdentifier` property in [Config.swift](PrivateSync/Config.swift) with your new iCloud container identifier.

### How it Works

* On first launch, the app creates a custom zone on the Private Database named “Contacts”, and subscribes to all record changes on that zone.
* When running on a device, the app also registers with APNs (Apple Push Notification service), which is the mechanism for receiving information about changes through the aforementioned subscription.
* After this initialization process, the app fetches the latest changes from the server, using a change token representing the last time changes were fetched and processed if available. On first launch, no local token is available, so all records are returned, and the token returned from this operation is saved.
* The app’s main UI displays a list of Contacts. When the user adds a new Contact through the UI, a new record is created and saved to the database, and if successful, also saves this to a local store. This will trigger the UI to update and include the new Contact on the main list view.
* Creating a new record triggers a notification to **other** devices which are registered for push notifications with the app through the `CKRecordZoneSubscription` created on first launch.
* Devices receiving this notification will react by fetching the latest changes on the zone using the last known change token, and receive only the set of records that have changed since that change token was received. The records are updated locally and the UI now reflects the latest database state once again.

### Example Flow

1. Run the app on a device. Latest changes are fetched and a change token is stored.
1. Repeat the above on a simulator, and add a new contact through the UI.
1. The device receives a background push notification flagging that a change has occurred.
1. The device fetches the changes, passing along the change token received in step 1. Only the new contact added in step 2 is returned and processed, and now shows on the UI.

### Things To Learn

* Creating a custom CloudKit Record Zone.
* Creating a CloudKit Subscription that listens to database changes and sends a `content-available` push notification on change events.
* Registering for push notifications with a SwiftUI-compatible `UIApplicationDelegate` class.
* Receiving and handling a `CKNotification`.
* Using a cached `CKServerChangeToken` to fetch only record changes and deletions since the last sync.
* Adding, removing, and merging remote changes into a local cache, and reflecting those changes live in a UI.

### Further Reading

* [Remote Records](https://developer.apple.com/documentation/cloudkit/remote_records)
* [CKServerChangeToken](https://developer.apple.com/documentation/cloudkit/ckserverchangetoken)
* [CKSubscription](https://developer.apple.com/documentation/cloudkit/cksubscription) and [CKRecordZoneSubscription](https://developer.apple.com/documentation/cloudkit/ckrecordzonesubscription)
* [CKRecordZoneNotification](https://developer.apple.com/documentation/cloudkit/ckrecordzonenotification)
