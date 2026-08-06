import Combine
import Foundation

private struct RuntimeMessageTemplate {
    private static let placeholder = "{value}"

    let source: String
    let localizationKey: String

    func captures(from message: String) -> [String]? {
        let segments = source.components(separatedBy: Self.placeholder)
        guard segments.count > 1, message.hasPrefix(segments[0]) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: segments[0].count)
        var captures: [String] = []

        for index in 1..<segments.count {
            let segment = segments[index]
            let isFinalSegment = index == segments.count - 1

            if segment.isEmpty && isFinalSegment {
                captures.append(String(message[cursor...]))
                cursor = message.endIndex
                continue
            }

            let options: String.CompareOptions = isFinalSegment ? .backwards : []
            guard let range = message.range(
                of: segment,
                options: options,
                range: cursor..<message.endIndex
            ) else {
                return nil
            }
            captures.append(String(message[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }

        return cursor == message.endIndex ? captures : nil
    }

    static let all: [RuntimeMessageTemplate] = [
        // Bluetooth transport errors and logs are emitted in English by the
        // shared CoreBluetooth client. Keep these patterns here so the app can
        // render them in its independently selected runtime language.
        .init(source: "Bluetooth is unavailable: {value}", localizationKey: "runtime.bluetooth.unavailable"),
        .init(source: "Could not connect: {value}", localizationKey: "runtime.bluetooth.connectionFailed"),
        .init(source: "The device disconnected: {value}", localizationKey: "runtime.bluetooth.disconnected"),
        .init(source: "Service discovery failed: {value}", localizationKey: "runtime.bluetooth.serviceDiscoveryFailed"),
        .init(source: "The device does not expose required service {value}.", localizationKey: "runtime.bluetooth.missingService"),
        .init(source: "Characteristic discovery failed: {value}", localizationKey: "runtime.bluetooth.characteristicDiscoveryFailed"),
        .init(source: "The device does not expose required characteristic {value}.", localizationKey: "runtime.bluetooth.missingCharacteristic"),
        .init(source: "Characteristic {value} does not support the required operation.", localizationKey: "runtime.bluetooth.unsupportedCharacteristic"),
        .init(source: "Notification subscription failed: {value}", localizationKey: "runtime.bluetooth.subscriptionFailed"),
        .init(source: "The {value} payload exceeds the Bluetooth limit of {value} bytes.", localizationKey: "runtime.bluetooth.payloadTooLarge"),
        .init(source: "The {value} write failed: {value}", localizationKey: "runtime.bluetooth.writeFailed"),
        .init(source: "Connecting to {value}.", localizationKey: "runtime.bluetooth.connecting"),
        .init(source: "Bluetooth is unavailable ({value}).", localizationKey: "runtime.bluetooth.unavailableState"),
        .init(source: "Found compatible device {value}.", localizationKey: "runtime.bluetooth.foundDevice"),
        .init(source: "A Bluetooth notification failed: {value}", localizationKey: "runtime.bluetooth.notificationFailed"),

        // Controller messages are intentionally kept as domain events in the
        // controller. This catalog translates their rendered legacy strings
        // without coupling BLE/session code to the app's presentation locale.
        .init(source: "Hay un ajuste anterior de {value} por recuperar; conecta el radio original antes de continuar", localizationKey: "runtime.controller.previousRecovery"),
        .init(source: "Conectado · {value}", localizationKey: "runtime.controller.connected"),
        .init(source: "Perfil cambiado a {value}", localizationKey: "runtime.controller.profileChanged"),
        .init(source: "El borrador de {value} se ajustó al rango común {value}", localizationKey: "runtime.controller.draftNormalized"),
        .init(source: "La configuración de {value} actualizó su rango de potencia", localizationKey: "runtime.controller.rangeUpdated"),
        .init(source: "Ajuste anterior preparado para recuperar {value}; falta pulsar Aplicar", localizationKey: "runtime.controller.recoveryPrepared"),
        .init(source: "Conectando con {value}", localizationKey: "runtime.controller.connecting"),
        .init(source: "Potencia global {value} · {value} · {value} en {value}", localizationKey: "runtime.controller.globalPowerLimited"),
        .init(source: "Potencia global {value} · {value}", localizationKey: "runtime.controller.globalPower"),
        .init(source: "{value} se ajustó a {value}, el mínimo común de sus flashes", localizationKey: "runtime.controller.normalizedToMinimum"),
        .init(source: "No se pudo preparar la secuencia: {value}", localizationKey: "runtime.controller.sequencePreparationFailed"),
        .init(source: "Enviando {value} · {value} · {value} · modelado {value} · beep {value}", localizationKey: "runtime.controller.sendingSnapshot"),
        .init(source: "{value} no tiene un ajuste completo para construir el comando", localizationKey: "runtime.controller.incompleteSetting"),
        .init(source: "Asigna al menos un modelo de flash a {value}", localizationKey: "runtime.controller.assignFlashModel"),
        .init(source: "La potencia elegida para {value} está fuera de su rango; usa {value} o más", localizationKey: "runtime.controller.powerOutsideRange"),
        .init(source: "El cambio de {value} no forma un comando válido", localizationKey: "runtime.controller.invalidChange"),
        .init(source: "FEC8 no tenía una instantánea correlacionada para {value}", localizationKey: "runtime.controller.fec8WithoutSnapshot"),
        .init(source: "FEC8 de {value} llegó antes del acuse GATT y se ignoró por seguridad", localizationKey: "runtime.controller.earlyFec8"),
        .init(source: "Write GATT aceptado para {value} · esperando FEC8", localizationKey: "runtime.controller.gattAccepted"),
        .init(source: "Cambio aplicado y confirmado por el radio para {value}", localizationKey: "runtime.controller.changeConfirmed"),
        .init(source: "Test no enviado: {value}", localizationKey: "runtime.controller.testNotSent"),
        .init(source: "El resultado del write de {value} es incierto; reconecta el mismo radio y recupera el ajuste anterior", localizationKey: "runtime.controller.uncertainWrite"),
        .init(source: "No se aplicó el grupo {value}: {value}", localizationKey: "runtime.controller.groupNotApplied"),
        .init(source: "El write GATT de {value} no confirmó en 5 segundos", localizationKey: "runtime.controller.gattTimeout"),
        .init(source: "Write aceptado para {value}, sin FEC8; ajuste anterior pendiente de recuperación", localizationKey: "runtime.controller.acceptedWithoutFec8"),
        .init(source: "FEC8 de {value} expiró; reconecta el mismo radio antes de restaurar", localizationKey: "runtime.controller.fec8Expired"),
        .init(source: "El grupo {value} no tiene un ajuste completo", localizationKey: "runtime.controller.workingGroupIncomplete"),
        .init(source: "El grupo {value} no tiene un rango manual válido", localizationKey: "runtime.controller.workingGroupInvalidRange"),
        .init(source: "Revisa los valores del grupo {value} antes de sincronizar", localizationKey: "runtime.controller.reviewWorkingGroup"),
        .init(source: "Sincronizando valores de {value} grupos", localizationKey: "runtime.controller.synchronizingValues"),
        .init(source: "Valores sincronizados · {value} de {value} grupos confirmados", localizationKey: "runtime.controller.valuesSynchronized"),
        .init(source: "Espacio de trabajo listo · {value}", localizationKey: "runtime.controller.workspaceReady"),
        .init(source: "Preset “{value}” guardado", localizationKey: "runtime.controller.presetSaved"),
        .init(source: "Preset “{value}” eliminado", localizationKey: "runtime.controller.presetDeleted"),
        .init(source: "El preset no es compatible con el rango del grupo {value}", localizationKey: "runtime.controller.presetRangeMismatch"),
        .init(source: "Preset “{value}” cargado · aún no enviado al radio", localizationKey: "runtime.controller.presetLoadedPending"),
        .init(source: "Preset “{value}” cargado · se enviará al conectar", localizationKey: "runtime.controller.presetLoadedForConnection"),
        .init(source: "El radio confirmó {value}, pero el valor no pudo guardarse localmente", localizationKey: "runtime.controller.confirmedNotPersisted"),
        .init(source: "No se pudo construir A0: {value}", localizationKey: "runtime.controller.globalFrameFailed"),
        .init(source: "El estado global no confirmó por GATT ({value}); reconecta para sincronizarlo de nuevo", localizationKey: "runtime.controller.globalGattFailed"),

        // Nested domain values can occur inside a controller or transport
        // message. Recursively localizing captures keeps those messages whole.
        .init(source: "La potencia solicitada excede el rango común del grupo (mínimo 1/{value}).", localizationKey: "runtime.protocol.powerOutsideCapability"),
        .init(source: "Fija · {value}%", localizationKey: "runtime.modeling.fixed")
    ]
}

/// The languages shipped by estrobo.
///
/// SwiftUI views can apply `language.locale` with
/// `.environment(\.locale, language.locale)`. Code that produces a `String`
/// before it reaches SwiftUI can use `localizedString` or `localizedFormat`
/// so it resolves against the same language-specific resource bundle.
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case en
    case es

    static let storageKey = "GodoxMacControlPrototype.appLanguage.v1"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Native language names keep the language picker understandable even if
    /// a localization resource is missing or damaged.
    var autonym: String {
        switch self {
        case .en:
            "English"
        case .es:
            "Español"
        }
    }

    var localizedNameKey: String {
        switch self {
        case .en:
            "language.english"
        case .es:
            "language.spanish"
        }
    }

    static var systemPreferred: AppLanguage {
        for identifier in Locale.preferredLanguages {
            let normalized = identifier
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            let languageCode = normalized.split(separator: "-").first.map(String.init)
            if languageCode == AppLanguage.es.rawValue { return .es }
            if languageCode == AppLanguage.en.rawValue { return .en }
        }
        return .en
    }

    func localizedBundle(in bundle: Bundle = .main) -> Bundle {
        guard let path = bundle.path(forResource: rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return bundle
        }
        return localizedBundle
    }

    func localizedString(
        _ key: String,
        table: String? = nil,
        value: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        localizedBundle(in: bundle).localizedString(
            forKey: key,
            value: value ?? key,
            table: table
        )
    }

    /// Concise call site used by views that already hold an `AppLanguage`.
    func localized(_ key: String, value: String? = nil) -> String {
        localizedString(key, value: value)
    }

    /// Localizes a rendered controller or Bluetooth message.
    ///
    /// Most messages resolve through an exact resource key. The small set of
    /// messages that interpolate a device, group, or error at the transport
    /// boundary are recognized here so switching language never leaves the
    /// activity strip in a mixed-language state.
    func localizedMessage(_ message: String) -> String {
        resolveRuntimeMessage(message, depth: 0) { localizedString($0) }
    }

    /// Test seam for validating the runtime catalog against the shipped
    /// dictionaries without requiring a built `.app` bundle.
    func localizedMessage(
        _ message: String,
        using translations: [String: String]
    ) -> String {
        resolveRuntimeMessage(message, depth: 0) { translations[$0] ?? $0 }
    }

    static var runtimeMessageLocalizationKeys: Set<String> {
        Set(RuntimeMessageTemplate.all.map(\.localizationKey))
    }

    private func resolveRuntimeMessage(
        _ message: String,
        depth: Int,
        lookup: (String) -> String
    ) -> String {
        let direct = lookup(message)
        if direct != message { return direct }
        guard depth < 8 else { return message }

        for template in RuntimeMessageTemplate.all {
            guard let captures = template.captures(from: message) else { continue }
            let format = lookup(template.localizationKey)
            guard format != template.localizationKey else { return message }
            let localizedCaptures: [CVarArg] = captures.map {
                resolveRuntimeMessage($0, depth: depth + 1, lookup: lookup) as CVarArg
            }
            return String(
                format: format,
                locale: locale,
                arguments: localizedCaptures
            )
        }

        return message
    }

    func localizedFormat(
        _ key: String,
        arguments: [CVarArg],
        table: String? = nil,
        value: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        String(
            format: localizedString(key, table: table, value: value, bundle: bundle),
            locale: locale,
            arguments: arguments
        )
    }

    func localizedFormat(
        _ key: String,
        _ arguments: CVarArg...,
        table: String? = nil,
        value: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        localizedFormat(
            key,
            arguments: arguments,
            table: table,
            value: value,
            bundle: bundle
        )
    }
}

/// Small injectable persistence seam matching the other local preferences in
/// the prototype. Unknown or absent values follow the user's macOS language.
struct AppLanguagePreferences {
    static let defaultStorageKey = AppLanguage.storageKey

    private let storageKey: String
    private let readString: (String) -> String?
    private let writeString: (String, String) -> Void

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = AppLanguagePreferences.defaultStorageKey
    ) {
        self.storageKey = storageKey
        readString = { defaults.string(forKey: $0) }
        writeString = { value, key in defaults.set(value, forKey: key) }
    }

    init(
        storageKey: String,
        readString: @escaping (String) -> String?,
        writeString: @escaping (String, String) -> Void
    ) {
        self.storageKey = storageKey
        self.readString = readString
        self.writeString = writeString
    }

    func load() -> AppLanguage {
        guard let rawValue = readString(storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .systemPreferred
        }
        return language
    }

    func save(_ language: AppLanguage) {
        writeString(language.rawValue, storageKey)
    }
}

/// Runtime language source for the app shell and language picker.
///
/// Keep one instance at the app root, inject it as an environment object, and
/// apply its locale to the root view. Changing `language` updates SwiftUI and
/// persists the choice immediately.
@MainActor
final class AppLanguageStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            preferences.save(language)
        }
    }

    private let preferences: AppLanguagePreferences

    init(preferences: AppLanguagePreferences = AppLanguagePreferences()) {
        self.preferences = preferences
        language = preferences.load()
    }

    var locale: Locale { language.locale }

    func select(_ language: AppLanguage) {
        self.language = language
    }

    func localizedString(_ key: String, value: String? = nil) -> String {
        language.localizedString(key, value: value)
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        language.localizedFormat(key, arguments: arguments)
    }
}
