import Foundation
import Security

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "Fallo de persistencia segura"
) {
    precondition(condition(), message)
}

@MainActor
private final class MemoryObjects {
    var objects: [String: Any] = [:]
    var acceptsWrites = true
    var rejectedRemovals: Set<String> = []

    func makeStore(vault: RadioCodeVault) -> SavedRadioStore {
        SavedRadioStore(
            storageKey: "catalog-v3",
            plaintextStorageKey: "plaintext-v2",
            legacyStorageKey: "plaintext-v1",
            vault: vault,
            readObject: { [weak self] in self?.objects[$0] },
            writeData: { [weak self] data, key in
                guard let self, self.acceptsWrites else { return false }
                self.objects[key] = data
                return true
            },
            removeValue: { [weak self] key in
                guard let self, !self.rejectedRemovals.contains(key) else {
                    return false
                }
                self.objects[key] = nil
                return true
            }
        )
    }
}

@MainActor
private final class ReadbackFailingJournal: RestorationJournal {
    var data: Data?
    private var failNextRead = false

    func read() -> RestorationJournalReadResult {
        if failNextRead {
            failNextRead = false
            return .failed(-77)
        }
        return data.map(RestorationJournalReadResult.data) ?? .none
    }

    func replace(with data: Data) -> RestorationJournalMutationResult {
        self.data = data
        failNextRead = true
        return .committed
    }

    func clear() -> RestorationJournalMutationResult {
        data = nil
        return .committed
    }
}

@main
@MainActor
enum SecurePersistenceCheck {
    private static let firstID = UUID(
        uuidString: "11111111-2222-3333-4444-555555555555"
    )!
    private static let secondID = UUID(
        uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    )!

    static func main() {
        checkRadioCodeRedactionAndMemoryVault()
        checkMetadataOnlyRoundTripAndOrdering()
        checkPlaintextMigrationFailureBoundaries()
        checkAtomicJournalDurabilityAndCorruption()
        checkUserDefaultsJournalMigrationBoundary()
        checkKeychainWhenAvailable()
        print("Secure persistence checks: OK")
    }

    private static func checkRadioCodeRedactionAndMemoryVault() {
        expect(RadioCode("12345") == nil)
        expect(RadioCode("12345A") == nil)
        guard let code = RadioCode("123456") else {
            preconditionFailure("No se construyó el código sintético")
        }
        expect(String(describing: code) == "<redacted>")
        expect(String(reflecting: code) == "RadioCode(<redacted>)")
        expect(!"\(code)".contains("123456"))

        let vault = InMemoryRadioCodeVault()
        expect(vault.read(deviceID: firstID) == .missing)
        expect(vault.store(code, deviceID: firstID) == .succeeded)
        expect(vault.read(deviceID: firstID) == .value(code))
        vault.nextStoreFailure = -1
        expect(vault.store(code, deviceID: secondID) == .failed(-1))
        expect(vault.read(deviceID: secondID) == .missing)
        expect(vault.remove(deviceID: firstID) == .succeeded)
        expect(vault.read(deviceID: firstID) == .missing)
    }

    private static func checkMetadataOnlyRoundTripAndOrdering() {
        let memory = MemoryObjects()
        let vault = InMemoryRadioCodeVault()
        let store = memory.makeStore(vault: vault)
        memory.objects["plaintext-v2"] = plaintextV2()

        guard case .records(let migrated) = store.load() else {
            preconditionFailure("V2 no migró")
        }
        expect(migrated.map(\.deviceID) == [firstID, secondID])
        expect(memory.objects["plaintext-v2"] == nil)
        guard let catalog = memory.objects["catalog-v3"] as? Data,
              let json = String(data: catalog, encoding: .utf8) else {
            preconditionFailure("No se publicó catálogo v3")
        }
        expect(json.contains("\"version\":3"))
        expect(!json.contains("radioCode"))
        expect(!json.contains("password"))
        expect(!json.contains("123456"))
        expect(!json.contains("654321"))

        guard let updated = SavedRadio(
            deviceID: firstID,
            name: "GDBH-A actualizado",
            radioCode: "222222"
        ) else {
            preconditionFailure("No se construyó actualización")
        }
        expect(store.upsert(updated))
        guard case .records(let afterUpdate) = store.load() else {
            preconditionFailure("No cargó actualización")
        }
        expect(afterUpdate.map(\.deviceID) == [firstID, secondID])
        expect(afterUpdate[0] == updated)
        expect(store.remove(deviceID: firstID))
        guard case .records(let afterForget) = store.load() else {
            preconditionFailure("Olvidar uno eliminó la biblioteca")
        }
        expect(afterForget.map(\.deviceID) == [secondID])
        expect(vault.read(deviceID: firstID) == .missing)
        expect(vault.read(deviceID: secondID) == .value(RadioCode("654321")!))
    }

    private static func checkPlaintextMigrationFailureBoundaries() {
        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v2"] = plaintextV2()
            vault.nextStoreFailure = -11
            expect(store.load() == .invalid, "vault write failure must fail closed")
            expect(memory.objects["plaintext-v2"] != nil, "vault write failure removed plaintext")
            expect(memory.objects["catalog-v3"] == nil, "vault write failure published catalog")
        }

        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v2"] = plaintextV2()
            vault.nextReadFailure = -12
            expect(store.load() == .invalid)
            expect(memory.objects["plaintext-v2"] != nil)
            expect(memory.objects["catalog-v3"] == nil)
        }

        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v2"] = plaintextV2()
            memory.acceptsWrites = false
            expect(store.load() == .invalid)
            expect(memory.objects["plaintext-v2"] != nil)
            expect(memory.objects["catalog-v3"] == nil)
        }

        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v2"] = plaintextV2()
            memory.rejectedRemovals = ["plaintext-v2"]
            expect(store.load() == .invalid)
            expect(memory.objects["catalog-v3"] != nil)
            expect(memory.objects["plaintext-v2"] != nil)
            memory.rejectedRemovals = []
            guard case .records(let retried) = store.load() else {
                preconditionFailure("La migración idempotente no cerró limpieza")
            }
            expect(retried.map(\.deviceID) == [firstID, secondID])
            expect(memory.objects["plaintext-v2"] == nil)
        }

        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v1"] = Data(
                #"{"version":1,"deviceID":"11111111-2222-3333-4444-555555555555","name":"GDBH-LEGACY","password":"123456"}"#.utf8
            )
            guard case .records(let migrated) = store.load() else {
                preconditionFailure("V1 no migró")
            }
            expect(migrated.count == 1)
            expect(memory.objects["plaintext-v1"] == nil)
            let catalog = memory.objects["catalog-v3"] as! Data
            expect(!String(decoding: catalog, as: UTF8.self).contains("123456"))
        }

        do {
            let memory = MemoryObjects()
            let vault = InMemoryRadioCodeVault()
            let store = memory.makeStore(vault: vault)
            memory.objects["plaintext-v2"] = plaintextV2()
            guard case .records(let before) = store.load() else {
                preconditionFailure("No preparó biblioteca para fallo de olvido")
            }
            vault.nextRemoveFailure = -13
            expect(!store.remove(deviceID: firstID))
            expect(store.load() == .records(before))
            expect(vault.read(deviceID: firstID) == .value(RadioCode("123456")!))
        }
    }

    private static func checkAtomicJournalDurabilityAndCorruption() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "estrobo-secure-persistence-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("restoration.json")
        let original = legacyRestorationV1()
        let replacement = Data("replacement".utf8)
        let journal = AtomicFileRestorationJournal(fileURL: url)

        expect(journal.replace(with: original) == .committed)
        expect(journal.read() == .data(original))
        let permissions = try! FileManager.default.attributesOfItem(atPath: url.path)[
            .posixPermissions
        ] as! NSNumber
        expect(permissions.intValue & 0o777 == 0o600)

        let preRenameFailure = AtomicFileRestorationJournal(
            fileURL: url,
            injectFailure: { $0 == .syncTemporary }
        )
        expect(preRenameFailure.replace(with: replacement) == .notCommitted)
        expect(journal.read() == .data(original))

        let postRenameFailure = AtomicFileRestorationJournal(
            fileURL: url,
            injectFailure: { $0 == .syncDirectory }
        )
        expect(postRenameFailure.replace(with: replacement) == .indeterminate)
        expect(journal.read() == .data(replacement))

        expect(journal.replace(with: Data("corrupt".utf8)) == .committed)
        let store = PendingRestorationStore(journal: journal)
        expect(store.load() == .invalid)
        expect(journal.read() == .data(Data("corrupt".utf8)))
        expect(store.clear())
        expect(journal.read() == .none)
    }

    private static func checkUserDefaultsJournalMigrationBoundary() {
        let key = "legacy-restoration"
        let legacyData = legacyRestorationV1()

        do {
            var legacy: [String: Any] = [key: legacyData]
            let journal = InMemoryRestorationJournal()
            let store = PendingRestorationStore(
                journal: journal,
                legacyStorageKey: key,
                readLegacyObject: { legacy[$0] },
                removeLegacyValue: { legacy[$0] = nil; return true }
            )
            guard case .record(let group, _) = store.load() else {
                preconditionFailure("No migró journal UserDefaults")
            }
            expect(group == .c)
            expect(journal.data == legacyData)
            expect(legacy[key] == nil)
        }

        do {
            var legacy: [String: Any] = [key: legacyData]
            let journal = InMemoryRestorationJournal()
            journal.nextReplaceResult = .notCommitted
            let store = PendingRestorationStore(
                journal: journal,
                legacyStorageKey: key,
                readLegacyObject: { legacy[$0] },
                removeLegacyValue: { legacy[$0] = nil; return true }
            )
            expect(store.load() == .invalid)
            expect(legacy[key] != nil)
            expect(journal.data == nil)
        }

        do {
            var legacy: [String: Any] = [key: legacyData]
            let journal = ReadbackFailingJournal()
            let store = PendingRestorationStore(
                journal: journal,
                legacyStorageKey: key,
                readLegacyObject: { legacy[$0] },
                removeLegacyValue: { legacy[$0] = nil; return true }
            )
            expect(store.load() == .invalid)
            expect(legacy[key] != nil)
        }

        let memory = InMemoryRestorationJournal(data: Data("bad-json".utf8))
        let corruptStore = PendingRestorationStore(journal: memory)
        expect(corruptStore.load() == .invalid)
        expect(memory.data == Data("bad-json".utf8))
    }

    private static func checkKeychainWhenAvailable() {
        let service = "mx.loo.estrobo.radio-code.test.\(UUID().uuidString)"
        let vault = KeychainRadioCodeVault(service: service)
        guard let code = RadioCode("314159") else { return }
        _ = vault.remove(deviceID: firstID)
        let write = vault.store(code, deviceID: firstID)
        guard write == .succeeded else {
            print("Keychain check: skipped (host status \(write))")
            return
        }
        expect(vault.read(deviceID: firstID) == .value(code))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: firstID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnAttributes as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        expect(
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            "Keychain attributes unavailable"
        )
        let attributes = result as! [String: Any]
        expect(
            attributes[kSecAttrService as String] as? String == service,
            "Keychain service mismatch"
        )
        expect(
            attributes[kSecAttrAccount as String] as? String == firstID.uuidString,
            "Keychain account mismatch"
        )
        if let accessibility = attributes[kSecAttrAccessible as String] {
            let returnedAccessibility = String(describing: accessibility)
            let acceptedAccessibility = [
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                // macOS may normalize the device-only variant. iOS preserves
                // the exact value set by the adapter above.
                kSecAttrAccessibleWhenUnlocked as String,
            ]
            expect(
                acceptedAccessibility.contains(returnedAccessibility),
                "Keychain accessibility mismatch"
            )
        }
        expect(vault.remove(deviceID: firstID) == .succeeded)
        expect(vault.read(deviceID: firstID) == .missing)
    }

    private static func plaintextV2() -> Data {
        Data(
            #"{"version":2,"radios":[{"deviceID":"11111111-2222-3333-4444-555555555555","name":"GDBH-A","radioCode":"123456"},{"deviceID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"Ami-B","radioCode":"654321"}]}"#.utf8
        )
    }

    private static func legacyRestorationV1() -> Data {
        Data(
            #"{"version":1,"group":12,"deviceID":"11111111-2222-3333-4444-555555555555","modeByte":1,"powerByte":77,"modelingIntensityByte":25,"beepByte":1,"modelingModeByte":2,"compensationByte":129}"#.utf8
        )
    }
}
