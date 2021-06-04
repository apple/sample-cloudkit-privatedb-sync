//
//  ViewModel.swift
//  (cloudkit-samples) Private Sync
//

import Foundation
import CloudKit
import Combine

final class ViewModel: ObservableObject {

    // MARK: - Properties

    // MARK: Published State

    /// Contacts by name to be displayed by our View.
    @Published private(set) var contactNames: [String] = []

    /// A dictionary mapping contact names (value) to ID (key).
    @Published private var contacts: [String: String] = [:]

    // MARK: CloudKit Properties

    /// The CloudKit container we'll use.
    private lazy var container = CKContainer(identifier: Config.containerIdentifier)
    /// For this sample we use the iCloud user's private database.
    private lazy var database = container.privateCloudDatabase
    /// We use a custom record zone to support fetching only changed records.
    private let zone = CKRecordZone(zoneName: "Contacts")
    /// Each subscription requires a unique ID.
    private let subscriptionID = "changes-subscription-id"
    /// We use a change token to inform the server of the last time we had the most recent remote data.
    private(set) var lastChangeToken: CKServerChangeToken?

    // MARK: Subscribers

    private var subscribers: [AnyCancellable] = []

    // MARK: - Public Functions

    init() {
        // For simplicity, observe the local cache and publish just the names (values) to the contactNames published var.
        $contacts.map { $0.values.sorted() }
            .assign(to: &$contactNames)
    }

    /// Loads any stored cache and change token, and creates custom zone and subscription as needed.
    func initialize() async throws {
        loadLocalCache()
        loadLastChangeToken()

        try await createZoneIfNeeded()
        try await createSubscriptionIfNeeded()
    }

    /// Using the last known change token, retrieve changes on the zone since the last time we pulled from iCloud.
    /// If `lastChangeToken` is `nil`, all records will be retrieved.
    func fetchLatestChanges() async throws {
        /// `recordZoneChanges` can return multiple consecutive changesets before completing, so
        /// we use a loop to process multiple results if needed, indicated by the `moreComing` flag.
        var awaitingChanges = true

        while awaitingChanges {
            /// Fetch changeset for the last known change token.
            let changes = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: lastChangeToken)

            /// Convert changes to `CKRecord` objects and deleted IDs.
            let changedRecords = changes.modificationResultsByID.compactMapValues { try? $0.get().record }
            let deletedRecordIDs = changes.deletions.map { $0.recordID.recordName }

            /// Update local state, processing changes/additions and deletions.
            changedRecords.forEach { id, record in
                if let contactName = record["name"] as? String {
                    contacts[id.recordName] = contactName
                }
            }

            deletedRecordIDs.forEach { contacts.removeValue(forKey: $0) }

            /// Save our new change token representing this point in time.
            saveChangeToken(changes.changeToken)

            /// Write updated local cache to disk.
            saveLocalCache()

            /// If there are more changes coming, we need to repeat this process with the new token.
            /// This is indicated by the returned changeset `moreComing` flag.
            awaitingChanges = changes.moreComing
        }
    }

    /// Creates a new Contact record in the local cache as well as on the remote database.
    /// For simplicity, if the remote operation fails, no local update occurs.
    /// - Parameters:
    ///   - name: The name of the new contact.
    func addContact(name: String) async throws {
        // We need to build a CKRecord of our new Contact using our custom zone and record type.
        let newRecordID = CKRecord.ID(zoneID: zone.zoneID)
        let newRecord = CKRecord(recordType: "Contact", recordID: newRecordID)
        newRecord["name"] = name

        let savedRecord = try await database.save(newRecord)

        /// At this point, the record has been successfully saved and we can add it to our local cache.
        /// If the `save` operation fails, an error is thrown before reaching this point.
        contacts[savedRecord.recordID.recordName] = name
        saveLocalCache()
    }

    /// Deletes a Contact record if found by name in the local cache as well as on the remote database.
    /// For simplicity, if the remote operation fails, no local update occurs.
    /// - Parameters:
    ///   - name: The name of the contact to delete.
    func deleteContact(name: String) async throws {
        // In this contrived example, Contact records only store a name, so rather than requiring the
        // unique ID to delete a Contact, we'll use the first ID that matches the name to delete.
        guard let matchingID = contacts.first(where: { _, value in name == value })?.key else {
            debugPrint("Contact not found on deletion for name: \(name)")
            throw PrivateSyncError.contactNotFound
        }

        let recordID = CKRecord.ID(recordName: matchingID, zoneID: zone.zoneID)

        try await database.deleteRecord(withID: recordID)

        /// At this point, the record has been successfully deleted.
        /// If the `deleteRecord` operation fails, an error is thrown before reaching this point.
        contacts.removeValue(forKey: matchingID)
        saveLocalCache()
    }

    // MARK: - Local Caching

    private func loadLocalCache() {
        contacts = UserDefaults.standard.dictionary(forKey: "contacts") as? [String: String] ?? [:]
    }

    private func saveLocalCache() {
        UserDefaults.standard.set(contacts, forKey: "contacts")
    }

    private func loadLastChangeToken() {
        guard let data = UserDefaults.standard.data(forKey: "lastChangeToken"),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) else {
            return
        }

        lastChangeToken = token
    }

    private func saveChangeToken(_ token: CKServerChangeToken) {
        let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)

        lastChangeToken = token
        UserDefaults.standard.set(tokenData, forKey: "lastChangeToken")
    }

    // MARK: - CloudKit Initialization Helpers

    /// Creates the custom zone defined by the `zone` property if needed.
    func createZoneIfNeeded() async throws {
        // Avoid the operation if this has already been done.
        guard !UserDefaults.standard.bool(forKey: "isZoneCreated") else {
            return
        }

        do {
            _ = try await database.modifyRecordZones(saving: [zone])
        } catch {
            print("ERROR: Failed to create custom zone: \(error.localizedDescription)")
            throw error
        }

        UserDefaults.standard.setValue(true, forKey: "isZoneCreated")
    }

    /// Creates a subscription if needed that tracks changes to our custom zone.
    func createSubscriptionIfNeeded() async throws {
        guard !UserDefaults.standard.bool(forKey: "isSubscribed") else {
            return
        }

        // First check if the subscription has already been created.
        // If a subscription is returned, we don't need to create one.
        let foundSubscription = try? await database.subscription(for: subscriptionID)
        guard foundSubscription == nil else {
            UserDefaults.standard.setValue(true, forKey: "isSubscribed")
            return
        }

        // No subscription created yet, so create one here, reporting and passing along any errors.
        let subscription = CKRecordZoneSubscription(zoneID: zone.zoneID, subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await database.modifySubscriptions(saving: [subscription])
        UserDefaults.standard.setValue(true, forKey: "isSubscribed")
    }

    // MARK: - Helper Error Type

    enum PrivateSyncError: Error {
        case contactNotFound
    }
}
