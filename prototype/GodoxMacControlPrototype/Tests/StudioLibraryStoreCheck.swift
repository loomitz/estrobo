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
        try checkLegacyV1Defaults()
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
        expect(preset?.multiFlashSettings == .default)
        expect(StudioPreset(
            name: "Restauración inválida sobre M",
            profileID: "gdbh-observed-0-f",
            groups: [.b],
            states: [.b: state],
            groupsRestoredAfterMulti: [.b]
        ) == nil)

        let multiState = snapshot(power: 50, modeling: .off, mode: .multi)
        let offState = snapshot(power: 50, modeling: .off, mode: .off)
        expect(StudioPreset(
            name: "Restauración sin Multi",
            profileID: "gdbh-observed-0-f",
            groups: [.b],
            states: [.b: offState],
            lastKnownActiveModes: [.b: .manual],
            groupsRestoredAfterMulti: [.b]
        ) == nil)
        expect(StudioPreset(
            name: "Mezcla insegura",
            profileID: "gdbh-observed-0-f",
            groups: [.b, .c],
            states: [.b: state, .c: multiState]
        ) == nil)
        expect(StudioPreset(
            name: "Origen inválido",
            profileID: "gdbh-observed-0-f",
            groups: [.c],
            states: [.c: multiState],
            lastKnownActiveModes: [.c: .multi]
        ) == nil)
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
        expect(StudioWorkspaceGroup(
            snapshot: state,
            assignedFlashModelIDs: ["ad600pro-ii"],
            restoresAfterMulti: true
        ) == nil)
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

        let workspace = StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b],
            visibleGroups: [.b],
            groupConfigurations: [.b: group]
        )
        expect(workspace?.multiFlashSettings == .default)
        let multiState = snapshot(power: 50, modeling: .off, mode: .multi)
        let offState = snapshot(power: 50, modeling: .off, mode: .off)
        guard let restoringOffGroup = StudioWorkspaceGroup(
            snapshot: offState,
            assignedFlashModelIDs: ["ad600pro-ii"],
            lastKnownActiveMode: .manual,
            restoresAfterMulti: true
        ) else {
            preconditionFailure("No se pudo construir el grupo Off restaurable")
        }
        expect(StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b],
            visibleGroups: [.b],
            groupConfigurations: [.b: restoringOffGroup]
        ) == nil)
        guard let multiGroup = StudioWorkspaceGroup(
            snapshot: multiState,
            assignedFlashModelIDs: ["ad400pro"],
            lastKnownActiveMode: .autoTTL
        ) else {
            preconditionFailure("No se pudo construir el grupo Multi válido")
        }
        expect(StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b, .c],
            visibleGroups: [.b],
            groupConfigurations: [.b: group, .c: multiGroup]
        ) == nil)
        expect(StudioWorkspaceGroup(
            snapshot: multiState,
            assignedFlashModelIDs: ["ad400pro"],
            lastKnownActiveMode: .multi
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
            mode: .off,
            compensation: 0x81
        )
        let cState = snapshot(
            power: 70,
            modeling: .proportional,
            beep: false,
            mode: .multi,
            compensation: 0x22
        )
        guard let workspaceMulti = MultiFlashSettings(
            power: multiPower(20),
            count: 7,
            hertz: 19
        ), let presetMulti = MultiFlashSettings(
            power: multiPower(70),
            count: 83,
            hertz: 100
        ) else {
            preconditionFailure("No se pudieron construir los ajustes Multi de prueba")
        }
        guard let bConfiguration = StudioWorkspaceGroup(
            snapshot: bState,
            assignedFlashModelIDs: ["ad600", "ad600pro-ii"],
            lastKnownActiveMode: .manual,
            restoresAfterMulti: true
        ), let cConfiguration = StudioWorkspaceGroup(
            snapshot: cState,
            assignedFlashModelIDs: ["ad400pro"],
            lastKnownActiveMode: .autoTTL,
            restoresAfterMulti: true
        ), let workspace = StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b, .c],
            visibleGroups: [.b],
            groupConfigurations: [
                .b: bConfiguration,
                .c: cConfiguration,
            ],
            multiFlashSettings: workspaceMulti
        ), let preset = StudioPreset(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Producto blanco",
            createdAt: Date(timeIntervalSince1970: 1_700_100_000.25),
            updatedAt: Date(timeIntervalSince1970: 1_700_100_900.75),
            profileID: "gdbh-observed-0-f",
            groups: [.c, .b],
            states: [.b: bState, .c: cState],
            lastKnownActiveModes: [.b: .manual, .c: .autoTTL],
            groupsRestoredAfterMulti: [.b, .c],
            multiFlashSettings: presetMulti
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
        expect(json.components(separatedBy: #""multiFlashSettings""#).count - 1 == 2)
        expect(json.contains(#""lastKnownActiveModeByte":0"#))
        expect(json.contains(#""lastKnownActiveModeByte":1"#))
        expect(json.components(separatedBy: #""restoresAfterMulti":true"#).count - 1 == 4)
        expect(json.contains(#""countByte":7"#))
        expect(json.contains(#""hertzByte":100"#))
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
        expect(decoded.workspace.multiFlashSettings == workspaceMulti)
        expect(decoded.presets.first?.multiFlashSettings == presetMulti)
        expect(decoded.workspace.groupConfigurations[.c]?.snapshot.operatingMode == .multi)
        expect(decoded.workspace.groupConfigurations[.b]?.restoresAfterMulti == true)
        expect(decoded.workspace.groupConfigurations[.c]?.restoresAfterMulti == true)
        expect(decoded.workspace.groupConfigurations[.c]?.lastKnownActiveMode == .autoTTL)
        expect(decoded.presets.first?.lastKnownActiveModes[.c] == .autoTTL)
        expect(decoded.presets.first?.groupsRestoredAfterMulti == [.b, .c])
    }

    private static func checkLegacyV1Defaults() throws {
        let memory = MemoryStudioLibraryStorage()
        let store = memory.makeStore()
        expect(store.save(makeMinimalLibrary()))
        guard let data = memory.object as? Data,
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var workspace = object["workspace"] as? [String: Any],
              var presets = object["presets"] as? [[String: Any]] else {
            preconditionFailure("No se pudo preparar un registro v1 anterior a Multi")
        }

        workspace.removeValue(forKey: "multiFlashSettings")
        if var groupStates = workspace["groupStates"] as? [[String: Any]] {
            for index in groupStates.indices {
                groupStates[index].removeValue(forKey: "lastKnownActiveModeByte")
            }
            workspace["groupStates"] = groupStates
        }
        for index in presets.indices {
            presets[index].removeValue(forKey: "multiFlashSettings")
            if var states = presets[index]["states"] as? [[String: Any]] {
                for stateIndex in states.indices {
                    states[stateIndex].removeValue(forKey: "lastKnownActiveModeByte")
                }
                presets[index]["states"] = states
            }
        }
        object["workspace"] = workspace
        object["presets"] = presets
        memory.object = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        guard case .record(let decoded) = store.load() else {
            preconditionFailure("Un registro v1 sin Multi debe conservar compatibilidad")
        }
        expect(decoded.workspace.multiFlashSettings == .default)
        expect(decoded.presets.allSatisfy { $0.multiFlashSettings == .default })
        expect(decoded.workspace.groupConfigurations[.b]?.lastKnownActiveMode == .manual)
        expect(decoded.workspace.groupConfigurations[.b]?.restoresAfterMulti == false)
        expect(decoded.presets.first?.groupsRestoredAfterMulti.isEmpty == true)

        expect(store.save(makeMultiRestorationLibrary()))
        guard let multiData = memory.object as? Data,
              var multiObject = try JSONSerialization.jsonObject(
                  with: multiData
              ) as? [String: Any],
              var multiWorkspace = multiObject["workspace"] as? [String: Any],
              var multiGroupStates = multiWorkspace["groupStates"] as? [[String: Any]],
              var multiPresets = multiObject["presets"] as? [[String: Any]] else {
            preconditionFailure("No se pudo preparar el v1 Multi sin flags")
        }
        for index in multiGroupStates.indices {
            multiGroupStates[index].removeValue(forKey: "restoresAfterMulti")
        }
        multiWorkspace["groupStates"] = multiGroupStates
        for index in multiPresets.indices {
            guard var states = multiPresets[index]["states"] as? [[String: Any]] else {
                preconditionFailure("El preset Multi no contenía estados")
            }
            for stateIndex in states.indices {
                states[stateIndex].removeValue(forKey: "restoresAfterMulti")
            }
            multiPresets[index]["states"] = states
        }
        multiObject["workspace"] = multiWorkspace
        multiObject["presets"] = multiPresets
        memory.object = try JSONSerialization.data(
            withJSONObject: multiObject,
            options: [.sortedKeys]
        )

        guard case .record(let legacyMulti) = store.load() else {
            preconditionFailure("El v1 Multi sin flags debe inferir la restauración")
        }
        expect(legacyMulti.workspace.groupConfigurations[.b]?.restoresAfterMulti == false)
        expect(legacyMulti.workspace.groupConfigurations[.c]?.restoresAfterMulti == true)
        expect(legacyMulti.presets.first?.groupsRestoredAfterMulti == [.c])
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

        expect(store.save(validLibrary))
        guard let multiData = memory.object as? Data,
              var invalidMultiObject = try JSONSerialization.jsonObject(
                  with: multiData
              ) as? [String: Any],
              var multiWorkspace = invalidMultiObject["workspace"] as? [String: Any],
              var workspaceMulti = multiWorkspace["multiFlashSettings"] as? [String: Any]
        else {
            preconditionFailure("No se pudo preparar el ajuste Multi corrupto")
        }
        workspaceMulti["countByte"] = 0
        multiWorkspace["multiFlashSettings"] = workspaceMulti
        invalidMultiObject["workspace"] = multiWorkspace
        memory.object = try JSONSerialization.data(
            withJSONObject: invalidMultiObject,
            options: [.sortedKeys]
        )
        expect(store.load() == .invalid)

        expect(store.save(validLibrary))
        guard let presetMultiData = memory.object as? Data,
              var invalidPresetMultiObject = try JSONSerialization.jsonObject(
                  with: presetMultiData
              ) as? [String: Any],
              var multiPresets = invalidPresetMultiObject["presets"] as? [[String: Any]],
              var firstPreset = multiPresets.first,
              var presetMulti = firstPreset["multiFlashSettings"] as? [String: Any]
        else {
            preconditionFailure("No se pudo preparar el Multi corrupto del preset")
        }
        presetMulti["hertzByte"] = 0
        firstPreset["multiFlashSettings"] = presetMulti
        multiPresets[0] = firstPreset
        invalidPresetMultiObject["presets"] = multiPresets
        memory.object = try JSONSerialization.data(
            withJSONObject: invalidPresetMultiObject,
            options: [.sortedKeys]
        )
        expect(store.load() == .invalid)

        expect(store.save(validLibrary))
        guard let restorationFlagData = memory.object as? Data,
              var invalidRestorationFlagObject = try JSONSerialization.jsonObject(
                  with: restorationFlagData
              ) as? [String: Any],
              var restorationWorkspace = invalidRestorationFlagObject["workspace"]
                as? [String: Any],
              var restorationStates = restorationWorkspace["groupStates"]
                as? [[String: Any]],
              !restorationStates.isEmpty else {
            preconditionFailure("No se pudo preparar el flag de restauración corrupto")
        }
        restorationStates[0]["restoresAfterMulti"] = true
        restorationWorkspace["groupStates"] = restorationStates
        invalidRestorationFlagObject["workspace"] = restorationWorkspace
        memory.object = try JSONSerialization.data(
            withJSONObject: invalidRestorationFlagObject,
            options: [.sortedKeys]
        )
        expect(store.load() == .invalid)

        expect(store.save(validLibrary))
        guard let noMultiFlagData = memory.object as? Data,
              var noMultiFlagObject = try JSONSerialization.jsonObject(
                  with: noMultiFlagData
              ) as? [String: Any],
              var noMultiWorkspace = noMultiFlagObject["workspace"] as? [String: Any],
              var noMultiStates = noMultiWorkspace["groupStates"] as? [[String: Any]],
              var noMultiState = noMultiStates.first,
              var noMultiA1 = noMultiState["state"] as? [String: Any] else {
            preconditionFailure("No se pudo preparar el flag Off sin Multi")
        }
        noMultiA1["modeByte"] = Int(GroupOperatingMode.off.rawValue)
        noMultiState["state"] = noMultiA1
        noMultiState["restoresAfterMulti"] = true
        noMultiStates[0] = noMultiState
        noMultiWorkspace["groupStates"] = noMultiStates
        noMultiFlagObject["workspace"] = noMultiWorkspace
        memory.object = try JSONSerialization.data(
            withJSONObject: noMultiFlagObject,
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

    private static func makeMultiRestorationLibrary() -> StudioLibrary {
        let offState = snapshot(power: 30, modeling: .off, mode: .off)
        let multiState = snapshot(power: 50, modeling: .off, mode: .multi)
        guard let offGroup = StudioWorkspaceGroup(
            snapshot: offState,
            assignedFlashModelIDs: ["ad600pro-ii"],
            lastKnownActiveMode: .manual,
            restoresAfterMulti: true
        ), let multiGroup = StudioWorkspaceGroup(
            snapshot: multiState,
            assignedFlashModelIDs: ["ad400pro"],
            lastKnownActiveMode: .autoTTL,
            restoresAfterMulti: true
        ), let workspace = StudioWorkspace(
            onboardingCompleted: true,
            profileID: "gdbh-observed-0-f",
            workingGroups: [.b, .c],
            visibleGroups: [.b, .c],
            groupConfigurations: [.b: offGroup, .c: multiGroup]
        ), let preset = StudioPreset(
            id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            name: "Escena Multi",
            createdAt: Date(timeIntervalSince1970: 1_700_200_000),
            profileID: "gdbh-observed-0-f",
            groups: [.b, .c],
            states: [.b: offState, .c: multiState],
            lastKnownActiveModes: [.b: .manual, .c: .autoTTL],
            groupsRestoredAfterMulti: [.b, .c]
        ), let library = StudioLibrary(workspace: workspace, presets: [preset]) else {
            preconditionFailure("No se pudo construir la biblioteca Multi restaurable")
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

    private static func multiPower(_ decimal: Int) -> ManualPower {
        guard let power = ManualPower.value(decimal: decimal),
              MultiFlashSettings.supportedPowers.contains(power) else {
            preconditionFailure("Potencia Multi de prueba inválida: \(decimal)")
        }
        return power
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
