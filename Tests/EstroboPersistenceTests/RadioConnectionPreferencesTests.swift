import XCTest
import EstroboCore
@testable import EstroboPersistence

final class RadioConnectionPreferencesTests: XCTestCase {
    @MainActor
    func testUserDefaultsJSONV1RoundTripsConnectionPreferences() throws {
        let suiteName = "EstroboPersistenceTests.RadioConnectionPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "connection-preferences"
        let store = RadioConnectionPreferences(
            defaults: defaults,
            storageKey: storageKey
        )
        let state = RadioConnectionPreferenceState(
            lastConnectedRadioID: UUID(),
            automaticConnectionRadioID: UUID()
        )

        XCTAssertTrue(store.save(state))
        XCTAssertEqual(store.load(), state)

        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(
            object["lastConnectedRadioID"] as? String,
            state.lastConnectedRadioID?.uuidString
        )
        XCTAssertEqual(
            object["automaticConnectionRadioID"] as? String,
            state.automaticConnectionRadioID?.uuidString
        )
    }

    @MainActor
    func testSeparateInMemoryFactoriesIsolateConnectionPreferences() {
        let first = PersistenceServicesFactory.inMemory()
        let second = PersistenceServicesFactory.inMemory()
        let state = RadioConnectionPreferenceState(
            lastConnectedRadioID: UUID(),
            automaticConnectionRadioID: UUID()
        )

        XCTAssertTrue(first.radioConnectionPreferences.save(state))
        XCTAssertEqual(first.radioConnectionPreferences.load(), state)
        XCTAssertEqual(
            second.radioConnectionPreferences.load(),
            RadioConnectionPreferenceState(
                lastConnectedRadioID: nil,
                automaticConnectionRadioID: nil
            )
        )
    }

    @MainActor
    func testInMemoryStorePersistsNilAndPresentIdentifiers() {
        let services = PersistenceServicesFactory.inMemory()
        let lastConnectedRadioID = UUID()
        let automaticConnectionRadioID = UUID()
        let states = [
            RadioConnectionPreferenceState(
                lastConnectedRadioID: nil,
                automaticConnectionRadioID: nil
            ),
            RadioConnectionPreferenceState(
                lastConnectedRadioID: lastConnectedRadioID,
                automaticConnectionRadioID: nil
            ),
            RadioConnectionPreferenceState(
                lastConnectedRadioID: nil,
                automaticConnectionRadioID: automaticConnectionRadioID
            ),
            RadioConnectionPreferenceState(
                lastConnectedRadioID: lastConnectedRadioID,
                automaticConnectionRadioID: automaticConnectionRadioID
            ),
        ]

        for state in states {
            XCTAssertTrue(services.radioConnectionPreferences.save(state))
            XCTAssertEqual(services.radioConnectionPreferences.load(), state)
        }
    }
}
