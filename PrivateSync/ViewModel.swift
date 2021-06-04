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

    /// Boolean representing if we have fully initialized yet (creating custom zone, creating subscription).
    @Published private(set) var isInitialized = false

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

    // MARK: Initialization State

    @Published private var isZoneCreated = false
    @Published private var isSubscriptionCreated = false

    // MARK: Subscribers

    private var subscribers: [AnyCancellable] = []

    // MARK: - Public Functions

    init() {
        // Determine live initialization state by combining zone creation and subscription creation state.
        Publishers.CombineLatest($isZoneCreated, $isSubscriptionCreated)
            .map { $0 && $1 }
            .assign(to: &$isInitialized)

        // For simplicity, observe the local cache and publish just the names (values) to the contactNames published var.
        $contacts.map { $0.values.sorted() }
            .assign(to: &$contactNames)
    }

    /// Performs all required initialization and fetches the latest changes from the CloudKit server.
    func initializeAndFetchLatestChanges() {
        loadLocalCache()
        loadLastChangeToken()

        // We need to create our zone first, as our subscription will reference the zone ID to track changes in.
        createZoneIfNeeded { result in
            guard case .success = result else {
                return
            }

            self.createSubscriptionIfNeeded()
        }

        // When isInitialized becomes true, we start fetching the latest changes.
        let sub = $isInitialized
            .filter { $0 }
            .sink { _ in
                self.fetchLatestChanges()
            }
        subscribers.append(sub)
    }

    /// Using the last known change token, retrieve changes on the zone since the last time we pulled from iCloud.
    /// If `lastChangeToken` is `nil`, all records will be retrieved.
    /// - Parameter completionHandler: An optional completion handler to handle the success or failure of the operation.
    func fetchLatestChanges(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        let options: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [
            zone.zoneID: .init(previousServerChangeToken: lastChangeToken)
        ]

        // Instead of performing changes as records come in one by one, we'll store them and update
        // our local store after completion, confirming no errors occurred.
        var changedRecords: [String: String] = [:]
        var deletedRecordIDs: [String] = []

        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone.zoneID], configurationsByRecordZoneID: options)

        // The operation executes this closure for each record in the record zone with changes
        operation.recordWasChangedBlock = { id, result in
            if let record = try? result.get(), let contactName = record["name"] as? String {
                DispatchQueue.main.async {
                    debugPrint("Adding contact: \(contactName)")
                    changedRecords[id.recordName] = contactName
                }
            }
        }

        // For each record deleted, store its ID to on completion update the local cache.
        operation.recordWithIDWasDeletedBlock = { recordID, recordType in
            deletedRecordIDs.append(recordID.recordName)
            debugPrint("Record \(recordID) of type \(recordType) deleted since last fetch.")
        }

        operation.recordZoneFetchResultBlock = { zoneID, result in
            switch result {
            case .success((let changeToken, _, _)):
                debugPrint("Finished zone fetch with token: \(changeToken)")
                DispatchQueue.main.async {
                    // We have our change set and no errors, so update our local store.
                    self.contacts.merge(changedRecords) { _, new in new }
                    // Remove any deleted records by ID.
                    deletedRecordIDs.forEach { self.contacts.removeValue(forKey: $0) }
                    // Save our new change token representing this point in time.
                    self.saveChangeToken(changeToken)
                    // Write our local cache to disk.
                    self.saveLocalCache()

                    completionHandler?(.success(()))
                }

            case .failure(let error):
                debugPrint("Error fetching zone changes: \(error.localizedDescription)")
                completionHandler?(.failure(error))
            }
        }

        database.add(operation)
    }

    /// Creates a new Contact record in the local cache as well as on the remote database.
    /// For simplicity, if the remote operation fails, no local update occurs.
    /// - Parameters:
    ///   - name: The name of the new contact.
    ///   - completionHandler: Handler to process success or failure.
    func addContactToLocalAndRemote(name: String, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        // We need to build a CKRecord of our new Contact using our custom zone and record type.
        let newRecordID = CKRecord.ID(zoneID: zone.zoneID)
        let newRecord = CKRecord(recordType: "Contact", recordID: newRecordID)
        newRecord["name"] = name

        let saveOperation = CKModifyRecordsOperation(recordsToSave: [newRecord])
        saveOperation.savePolicy = .allKeys

        var addedRecords: [CKRecord] = []

        saveOperation.perRecordSaveBlock = { _, result in
            if let record = try? result.get() {
                addedRecords.append(record)
            }
        }

        saveOperation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                addedRecords.forEach { record in
                    if let name = record["name"] as? String {
                        self.contacts[record.recordID.recordName] = name
                    }
                }

                self.saveLocalCache()
                completionHandler(result)
            }
        }

        database.add(saveOperation)
    }

    func deleteContactFromLocalAndRemote(name: String, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        // In this contrived example, Contact records only store a name, so rather than requiring the
        // unique ID to delete a Contact, we'll use the first ID that matches the name to delete.
        guard let matchingID = contacts.first(where: { _, value in name == value })?.key else {
            debugPrint("Contact not found on deletion for name: \(name)")
            completionHandler(.failure(PrivateSyncError.contactNotFound))
            return
        }

        let recordID = CKRecord.ID(recordName: matchingID, zoneID: zone.zoneID)
        let deleteOperation = CKModifyRecordsOperation(recordIDsToDelete: [recordID])

        deleteOperation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    debugPrint("Error deleting contact: \(error)")
                case .success:
                    self.contacts.removeValue(forKey: matchingID)
                    self.saveLocalCache()
                }

                completionHandler(result)
            }
        }

        database.add(deleteOperation)
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
    /// - Parameter completionHandler: An optional completion handler to track operation completion or errors.
    func createZoneIfNeeded(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        // Avoid the operation if this has already been done.
        guard !UserDefaults.standard.bool(forKey: "isZoneCreated") else {
            isZoneCreated = true
            completionHandler?(.success(()))
            return
        }

        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone])

        createZoneOperation.modifyRecordZonesResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    debugPrint("ERROR: Failed to create custom zone: \(error.localizedDescription)")

                case .success:
                    self.isZoneCreated = true
                    UserDefaults.standard.setValue(true, forKey: "isZoneCreated")
                }

                completionHandler?(result)
            }
        }

        database.add(createZoneOperation)
    }

    /// Creates a subscription if needed that tracks changes to our custom zone.
    /// - Parameter completionHandler: An optional completion handler to track operation completion or errors.
    private func createSubscriptionIfNeeded(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        guard !UserDefaults.standard.bool(forKey: "isSubscribed") else {
            isSubscriptionCreated = true
            completionHandler?(.success(()))
            return
        }

        let subscriptionID = self.subscriptionID

        // Check first if subscription has already been created.
        let fetchSubscription = CKFetchSubscriptionsOperation(subscriptionIDs: [subscriptionID])
        var didFindSubscription = false

        fetchSubscription.perSubscriptionResultBlock = { resultID, _ in
            if resultID == subscriptionID {
                didFindSubscription = true
            }
        }

        fetchSubscription.fetchSubscriptionsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure:
                    completionHandler?(result)

                case .success:
                    if !didFindSubscription {
                        // Subscription not found, so forward completion handler on and create it.
                        self.createSubscription(completionHandler: completionHandler)
                    } else {
                        self.isSubscriptionCreated = true
                        UserDefaults.standard.setValue(true, forKey: "isSubscribed")
                        completionHandler?(result)
                    }
                }
            }
        }

        database.add(fetchSubscription)
    }

    private func createSubscription(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        let subscription = CKRecordZoneSubscription(zoneID: zone.zoneID, subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let subscriptionOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription])
        subscriptionOperation.modifySubscriptionsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    debugPrint("ERROR: Failed creating subscription: \(error)")

                case .success:
                    debugPrint("SUCCESS: Created subscription.")
                    self.isSubscriptionCreated = true
                    UserDefaults.standard.setValue(true, forKey: "isSubscribed")
                }

                completionHandler?(result)
            }
        }

        database.add(subscriptionOperation)
    }

    // MARK: - Helper Error Type

    enum PrivateSyncError: Error {
        case contactNotFound
    }
}
