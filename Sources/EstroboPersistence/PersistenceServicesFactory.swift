import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// The persistence seam consumed by composition roots.
///
/// Concrete UserDefaults, Keychain and journal adapters remain implementation
/// details of this module. Callers receive only the Core ports they need.
@MainActor
public struct PersistenceServices {
    public let savedRadios: any SavedRadioRepository
    public let restorations: any RestorationRepository
    public let studioLibrary: any StudioLibraryRepository
    public let groupVisibility: any GroupVisibilityPreferencesStore
    public let changeDelivery: any ChangeDeliveryPreferencesStore
    public let transmitterProfiles: any TransmitterProfilePreferencesStore

    init(
        savedRadios: any SavedRadioRepository,
        restorations: any RestorationRepository,
        studioLibrary: any StudioLibraryRepository,
        groupVisibility: any GroupVisibilityPreferencesStore,
        changeDelivery: any ChangeDeliveryPreferencesStore,
        transmitterProfiles: any TransmitterProfilePreferencesStore
    ) {
        self.savedRadios = savedRadios
        self.restorations = restorations
        self.studioLibrary = studioLibrary
        self.groupVisibility = groupVisibility
        self.changeDelivery = changeDelivery
        self.transmitterProfiles = transmitterProfiles
    }
}

@MainActor
public enum PersistenceServicesFactory {
    /// Live device storage: Keychain for credentials, a crash-durable journal
    /// for recovery, and UserDefaults only for non-secret metadata/preferences.
    public static func live() -> PersistenceServices {
        PersistenceServices(
            savedRadios: SavedRadioStore(),
            restorations: PendingRestorationStore(),
            studioLibrary: StudioLibraryStore(),
            groupVisibility: LocalGroupPreferences(),
            changeDelivery: ChangeDeliveryPreferences(),
            transmitterProfiles: TransmitterProfilePreferences()
        )
    }

    /// Process-local storage for Demo mode, previews and deterministic tests.
    /// It never opens Keychain, a recovery file, or UserDefaults.
    public static func inMemory() -> PersistenceServices {
        let storage = InMemoryPersistenceStorage()
        let vault = InMemoryRadioCodeVault()
        let journal = InMemoryRestorationJournal()

        return PersistenceServices(
            savedRadios: SavedRadioStore(
                storageKey: SavedRadioStore.defaultStorageKey,
                vault: vault,
                readObject: storage.read,
                writeData: storage.write,
                removeValue: storage.remove
            ),
            restorations: PendingRestorationStore(journal: journal),
            studioLibrary: StudioLibraryStore(
                storageKey: StudioLibraryStore.defaultStorageKey,
                readObject: storage.read,
                writeData: storage.write
            ),
            groupVisibility: LocalGroupPreferences(
                storageKey: LocalGroupPreferences.defaultStorageKey,
                readArray: storage.readArray,
                writeIntegers: storage.writeIntegers
            ),
            changeDelivery: ChangeDeliveryPreferences(
                storageKey: ChangeDeliveryPreferences.defaultStorageKey,
                readString: storage.readString,
                writeString: storage.writeString
            ),
            transmitterProfiles: TransmitterProfilePreferences(
                storageKey: TransmitterProfilePreferences.defaultStorageKey,
                readObject: storage.read,
                writeData: storage.write
            )
        )
    }
}

@MainActor
private final class InMemoryPersistenceStorage {
    private var values: [String: Any] = [:]

    func read(_ key: String) -> Any? {
        values[key]
    }

    func write(_ data: Data, _ key: String) -> Bool {
        values[key] = data
        return values[key] as? Data == data
    }

    func remove(_ key: String) -> Bool {
        values[key] = nil
        return values[key] == nil
    }

    func readArray(_ key: String) -> [Any]? {
        values[key] as? [Any]
    }

    func writeIntegers(_ integers: [Int], _ key: String) {
        values[key] = integers
    }

    func readString(_ key: String) -> String? {
        values[key] as? String
    }

    func writeString(_ value: String, _ key: String) {
        values[key] = value
    }
}
