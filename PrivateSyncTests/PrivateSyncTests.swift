//
//  PrivateSyncTests.swift
//  (cloudkit-samples) Private Sync
//

import XCTest
import CloudKit
@testable import PrivateSync

class PrivateSyncTests: XCTestCase {

    override func setUp() {
        let vm = ViewModel()
        let expectation = self.expectation(description: "Expect successful zone creation.")

        Task {
            do {
                try await vm.createZoneIfNeeded()
            } catch {
                XCTFail("Failed to create record zone (VM initialization step): \(error)")
            }

            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func test_CloudKitReadiness() async throws {
        // Fetch zones from the Private Database of the CKContainer for the current user to test for valid/ready state
        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase

        do {
            _ = try await database.allRecordZones()
        } catch let error as CKError {
            switch error.code {
            case .badContainer, .badDatabase:
                XCTFail("Create or select a CloudKit container in this app target's Signing & Capabilities in Xcode")

            case .permissionFailure, .notAuthenticated:
                XCTFail("Simulator or device running this app needs a signed-in iCloud account")

            default:
                XCTFail("CKError: \(error)")
            }
        }
    }

    func testFetchingChangesAndUpdatingToken() async throws {
        let vm = ViewModel()
        XCTAssert(vm.lastChangeToken == nil, "Expected new VM change token to start as nil.")

        try await vm.fetchLatestChanges()
        XCTAssert(vm.lastChangeToken != nil, "Expected change token after fetch to be non-nil.")
    }

}
