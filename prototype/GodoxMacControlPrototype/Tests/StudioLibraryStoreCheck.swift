import Foundation

private final class MemoryStudioLibraryStorage {
    var object: Any?
    var acceptsWrites = true

    func makeStore() -> StudioLibraryStore {
        StudioLibraryStore(
            storageKey: "studio-library-test",
            readObject: { [weak self] _ in self?.object },
            writeData: { [weak self] data, _ in
                guard let self, self.acceptsWrites else { return false }
                self.object = data
                return true
            }
        )
    }
}

@main
enum StudioLibraryStoreCheck {
    static func main() throws {
        checkPresetNameValidation()
        checkWorkspaceValidation()
        try checkVersionedRoundTrip()
        try checkCorruptAndUnknownRecords()
        checkWriteFailure()
        print("Workspace y presets versionados verificados sin credenciales ni UserDefaults reales")
    }

    private static func checkPresetNameValidation() {
        let state = snapshot(
            power: 23,
            modeling: .fixed(percent: 37),
            beep: true,
            mode: .manual,
            compensation: 0x81
        )
        expect(StudioPreset(
            name: "",
            profileID: "gdbh-observed-0-f",
            groups: [.b],
            states: [.b: state]
        ) == nil)
        expect(StudioPreset(
            name: "  \n\t ",
            profileID: "gdbh-observed-0-f",
            groups: [.b],
            states: [.b: state]
        ) == nil)

        let preset = StudioPreset(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "  Retrato principal  ",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            profileID: "  gdbh-observed-0-f  ",
            groups: [.b],
            states: [.b: state]
        )
        expect(preset?.name == "Retrato principal")
        expect(preset?.profileID == "gdbh-observed-0-f")
    }

    private static func checkWorkspaceValidation() {
        let state = snapshot(power: 30, modeling: .off)
        guard let group = StudioWorkspaceGroup(
            snapshot: state,
            assignedFlashModelIDs: [" ad600pro-ii "]
        ) else {
            preconditionFailure("No se pudo construir un grupo válido")
        }
        expect(group.assignedFlashModelIDs == ["ad600pro-ii"])
        expect(StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [],
            visibleGroups: [],
            groupConfigurations: [:]
        ) == nil)
        expect(StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b],
            visibleGroups: [.c],
            groupConfigurations: [.b: group]
        ) == nil)
        expect(StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b, .b],
            visibleGroups: [.b],
            groupConfigurations: [.b: group]
        ) == nil)
    }

    private static func checkVersionedRoundTrip() throws {
        let memory = MemoryStudioLibraryStorage()
        let store = memory.makeStore()
        expect(store.load() == .none)

        let bState = snapshot(
            power: 23,
            modeling: .fixed(percent: 37),
            beep: true,
            mode: .manual,
            compensation: 0x81
        )
        let cState = snapshot(
            power: 70,
            modeling: .proportional,
            beep: false,
            mode: .off,
            compensation: 0x22
        )
        guard let bConfiguration = StudioWorkspaceGroup(
            snapshot: bState,
            assignedFlashModelIDs: ["ad600", "ad600pro-ii"]
        ), let cConfiguration = StudioWorkspaceGroup(
            snapshot: cState,
            assignedFlashModelIDs: ["ad400pro"]
        ), let workspace = StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b, .c],
            visibleGroups: [.b],
            groupConfigurations: [
                .b: bConfiguration,
                .c: cConfiguration,
            ]
        ), let preset = StudioPreset(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Producto blanco",
            createdAt: Date(timeIntervalSince1970: 1_700_100_000.25),
            updatedAt: Date(timeIntervalSince1970: 1_700_100_900.75),
            profileID: "gdbh-observed-0-f",
            groups: [.c, .b],
            states: [.b: bState, .c: cState]
        ), let library = StudioLibrary(workspace: workspace, presets: [preset]) else {
            preconditionFailure("No se pudo construir la biblioteca válida")
        }

        expect(store.save(library))
        expect(store.load() == .record(library))

        guard let data = memory.object as? Data,
              let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("La biblioteca no produjo JSON")
        }
        expect(json.contains(#""version":1"#))
        expect(json.contains(#""onboardingCompleted":true"#))
        expect(json.contains(#""workingGroups""#))
        expect(json.contains(#""visibleGroups""#))
        expect(json.contains(#""assignedFlashModelIDs""#))
        expect(!json.contains(#""deviceID""#))
        expect(!json.contains(#""password""#))
        expect(!json.contains(#""radioCode""#))
        expect(!json.contains(#""credential""#))
        expect(!json.contains("908172"))

        guard case .record(let decoded) = store.load(),
              let decodedB = decoded.workspace.groupConfigurations[.b]?.snapshot,
              let decodedPresetB = decoded.presets.first?.states[.b] else {
            preconditionFailure("No se recuperaron los estados A1")
        }
        expectA1Bytes(decodedB, equalTo: bState)
        expectA1Bytes(decodedPresetB, equalTo: bState)
        expect(decoded.workspace.workingGroups == [.b, .c])
        expect(decoded.workspace.visibleGroups == [.b])
    }

    private static func checkCorruptAndUnknownRecords() throws {
        let memory = MemoryStudioLibraryStorage()
        let store = memory.makeStore()
        memory.object = Data([0x00, 0x01, 0x02])
        expect(store.load() == .invalid)
        memory.object = "no es Data"
        expect(store.load() == .invalid)

        let validLibrary = makeMinimalLibrary()
        expect(store.save(validLibrary))
        guard let validData = memory.object as? Data,
              var object = try JSONSerialization.jsonObject(with: validData) as? [String: Any] else {
            preconditionFailure("No se pudo inspeccionar el JSON válido")
        }

        object["version"] = 999
        memory.object = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        expect(store.load() == .invalid)

        expect(store.save(validLibrary))
        guard let groupData = memory.object as? Data,
              var invalidGroupObject = try JSONSerialization.jsonObject(
                  with: groupData
              ) as? [String: Any],
              var workspace = invalidGroupObject["workspace"] as? [String: Any],
              var states = workspace["groupStates"] as? [[String: Any]],
              !states.isEmpty else {
            preconditionFailure("No se pudo preparar el grupo corrupto")
        }
        states[0]["group"] = 255
        workspace["groupStates"] = states
        invalidGroupObject["workspace"] = workspace
        memory.object = try JSONSerialization.data(
            withJSONObject: invalidGroupObject,
            options: [.sortedKeys]
        )
        expect(store.load() == .invalid)

        expect(store.save(validLibrary))
        guard let a1Data = memory.object as? Data,
              var invalidA1Object = try JSONSerialization.jsonObject(
                  with: a1Data
              ) as? [String: Any],
              var a1Workspace = invalidA1Object["workspace"] as? [String: Any],
              var a1States = a1Workspace["groupStates"] as? [[String: Any]],
              var firstState = a1States.first,
              var a1 = firstState["state"] as? [String: Any] else {
            preconditionFailure("No se pudo preparar el A1 corrupto")
        }
        a1["modelingModeByte"] = 9
        firstState["state"] = a1
        a1States[0] = firstState
        a1Workspace["groupStates"] = a1States
        invalidA1Object["workspace"] = a1Workspace
        memory.object = try JSONSerialization.data(
            withJSONObject: invalidA1Object,
            options: [.sortedKeys]
        )
        expect(store.load() == .invalid)
    }

    private static func checkWriteFailure() {
        let memory = MemoryStudioLibraryStorage()
        memory.acceptsWrites = false
        let store = memory.makeStore()
        expect(!store.save(makeMinimalLibrary()))
        expect(store.load() == .none)
    }

    private static func makeMinimalLibrary() -> StudioLibrary {
        let state = snapshot(power: 30, modeling: .off)
        guard let group = StudioWorkspaceGroup(
            snapshot: state,
            assignedFlashModelIDs: ["ad600pro-ii"]
        ), let workspace = StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b],
            visibleGroups: [.b],
            groupConfigurations: [.b: group]
        ), let preset = StudioPreset(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            name: "Base",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profileID: "gdbh-observed-0-f",
            groups: [.b],
            states: [.b: state]
        ), let library = StudioLibrary(workspace: workspace, presets: [preset]) else {
            preconditionFailure("No se pudo construir la biblioteca mínima")
        }
        return library
    }

    private static func snapshot(
        power decimal: Int,
        modeling: ModelingLight,
        beep: Bool = false,
        mode: GroupOperatingMode = .manual,
        compensation: UInt8 = 0
    ) -> ManualGroupSnapshot {
        guard let power = ManualPower.value(decimal: decimal) else {
            preconditionFailure("Potencia de prueba no canónica: \(decimal)")
        }
        return ManualGroupSnapshot(
            power: power,
            modeling: modeling,
            beepEnabled: beep,
            operatingMode: mode,
            compensationByte: compensation
        )
    }

    private static func expectA1Bytes(
        _ actual: ManualGroupSnapshot,
        equalTo expected: ManualGroupSnapshot
    ) {
        expect(actual.operatingMode.rawValue == expected.operatingMode.rawValue)
        expect(actual.power.encodedByte == expected.power.encodedByte)
        expect(actual.modelingState.intensityByte == expected.modelingState.intensityByte)
        expect(actual.beepByte == expected.beepByte)
        expect(actual.modelingState.mode.rawValue == expected.modelingState.mode.rawValue)
        expect(actual.compensationByte == expected.compensationByte)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Verificación fallida"
    ) {
        guard condition() else { preconditionFailure(message) }
    }
}
