import Foundation

@main
enum AppLocalizationCheck {
    static func main() throws {
        let english = try loadTranslations(languageCode: "en")
        let spanish = try loadTranslations(languageCode: "es")

        checkResourceParity(english: english, spanish: spanish)
        checkRuntimeCatalogCoverage(english: english, spanish: spanish)
        checkWorkspaceConfigurationCopy(english: english, spanish: spanish)
        checkBluetoothMessages(english: english, spanish: spanish)
        checkControllerMessages(english: english, spanish: spanish)
        checkPreferences()

        print("English/Spanish resources, runtime messages, and language preferences verified")
    }

    private static func checkResourceParity(
        english: [String: String],
        spanish: [String: String]
    ) {
        let englishKeys = Set(english.keys)
        let spanishKeys = Set(spanish.keys)

        expect(
            englishKeys == spanishKeys,
            "Localization resource keys differ. Missing in English: "
                + spanishKeys.subtracting(englishKeys).sorted().joined(separator: ", ")
                + "; missing in Spanish: "
                + englishKeys.subtracting(spanishKeys).sorted().joined(separator: ", ")
        )
    }

    private static func checkRuntimeCatalogCoverage(
        english: [String: String],
        spanish: [String: String]
    ) {
        let runtimeKeys = AppLanguage.runtimeMessageLocalizationKeys
        let missingEnglish = runtimeKeys.subtracting(english.keys)
        let missingSpanish = runtimeKeys.subtracting(spanish.keys)

        expect(
            missingEnglish.isEmpty,
            "English is missing runtime keys: \(missingEnglish.sorted().joined(separator: ", "))"
        )
        expect(
            missingSpanish.isEmpty,
            "Spanish is missing runtime keys: \(missingSpanish.sorted().joined(separator: ", "))"
        )
    }

    private static func checkWorkspaceConfigurationCopy(
        english: [String: String],
        spanish: [String: String]
    ) {
        assertLocalized(
            "Organiza el transmisor, los grupos y sus flashes en un solo lugar.",
            english: "Organize the transmitter, groups, and their flashes in one place.",
            spanish: "Organiza el transmisor, los grupos y sus flashes en un solo lugar.",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Administrar perfiles",
            english: "Manage profiles",
            spanish: "Administrar perfiles",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Quitar un perfil sólo lo oculta en este Mac; puedes restaurarlo después.",
            english: "Removing a profile only hides it on this Mac; you can restore it later.",
            spanish: "Quitar un perfil sólo lo oculta en este Mac; puedes restaurarlo después.",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Quitar",
            english: "Remove",
            spanish: "Quitar",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "1 grupo seleccionado",
            english: "1 group selected",
            spanish: "1 grupo seleccionado",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "%lld grupos seleccionados",
            english: "%lld groups selected",
            spanish: "%lld grupos seleccionados",
            englishTranslations: english,
            spanishTranslations: spanish
        )
    }

    private static func checkBluetoothMessages(
        english: [String: String],
        spanish: [String: String]
    ) {
        assertLocalized(
            "Could not connect: unknown error",
            english: "Could not connect: unknown error",
            spanish: "No se pudo conectar: error desconocido",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "The device disconnected: powered off",
            english: "The device disconnected: powered off",
            spanish: "El dispositivo se desconectó: apagado",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Service discovery failed: permission denied",
            english: "Service discovery failed: permission denied",
            spanish: "Falló el descubrimiento de servicios: permiso denegado",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "The device does not expose required characteristic FFF3.",
            english: "The device does not expose required characteristic FFF3.",
            spanish: "El dispositivo no expone la característica requerida FFF3.",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Notification subscription failed: the device declined notifications",
            english: "Notification subscription failed: the device declined notifications",
            spanish: "Falló la suscripción a notificaciones: el dispositivo rechazó las notificaciones",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "A Bluetooth notification failed: unknown error",
            english: "A Bluetooth notification failed: unknown error",
            spanish: "Falló una notificación Bluetooth: error desconocido",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "The control write failed: The Godox device is not ready for commands.",
            english: "The control write failed: The Godox device is not ready for commands.",
            spanish: "Falló la escritura de control: El dispositivo Godox no está listo para recibir comandos.",
            englishTranslations: english,
            spanishTranslations: spanish
        )
    }

    private static func checkControllerMessages(
        english: [String: String],
        spanish: [String: String]
    ) {
        assertLocalized(
            "Hay un ajuste anterior de B por recuperar; conecta el radio original antes de continuar",
            english: "A previous B setting must be restored; connect the original trigger before continuing",
            spanish: "Hay un ajuste anterior de B por recuperar; conecta el radio original antes de continuar",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "FEC8 de C llegó antes del acuse GATT y se ignoró por seguridad",
            english: "FEC8 for C arrived before the GATT acknowledgement and was ignored for safety",
            spanish: "FEC8 de C llegó antes del acuse GATT y se ignoró por seguridad",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "La potencia elegida para D está fuera de su rango; usa 1/512 +0.0 o más",
            english: "The selected power for D is outside its range; use 1/512 +0.0 or higher",
            spanish: "La potencia elegida para D está fuera de su rango; usa 1/512 +0.0 o más",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Enviando A · M · 1/16 +0.3 · modelado Fija · 25% · beep on",
            english: "Sending A · M · 1/16 +0.3 · modeling Fixed · 25% · beep on",
            spanish: "Enviando A · M · 1/16 +0.3 · modelado Fija · 25% · beep encendido",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "No se aplicó el grupo E: La potencia solicitada excede el rango común del grupo (mínimo 1/512).",
            english: "Group E was not applied: The requested power exceeds the group's common range (minimum 1/512).",
            spanish: "No se aplicó el grupo E: La potencia solicitada excede el rango común del grupo (mínimo 1/512).",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Potencia global +0.3 · A, C · B en 1/128 +0.0",
            english: "Global power +0.3 · A, C · B at 1/128 +0.0",
            spanish: "Potencia global +0.3 · A, C · B en 1/128 +0.0",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Valores sincronizados · 2 de 2 grupos confirmados",
            english: "Values synced · 2 of 2 groups confirmed",
            spanish: "Valores sincronizados · 2 de 2 grupos confirmados",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "El grupo C no tiene un rango manual válido",
            english: "Group C does not have a valid manual range",
            spanish: "El grupo C no tiene un rango manual válido",
            englishTranslations: english,
            spanishTranslations: spanish
        )
        assertLocalized(
            "Preset “Retrato” cargado · aún no enviado al radio",
            english: "Preset “Retrato” loaded · not sent to the trigger yet",
            spanish: "Preset “Retrato” cargado · aún no enviado al radio",
            englishTranslations: english,
            spanishTranslations: spanish
        )

        let unknown = "Mensaje nuevo todavía sin catálogo"
        expect(
            AppLanguage.en.localizedMessage(unknown, using: english) == unknown,
            "Unknown runtime messages must remain readable"
        )
    }

    private static func checkPreferences() {
        let key = "test.language"
        var values: [String: String] = [:]
        let preferences = AppLanguagePreferences(
            storageKey: key,
            readString: { values[$0] },
            writeString: { value, storageKey in values[storageKey] = value }
        )

        expect(
            preferences.load() == AppLanguage.systemPreferred,
            "An absent preference must follow the system language"
        )
        values[key] = "unsupported"
        expect(
            preferences.load() == AppLanguage.systemPreferred,
            "An invalid preference must follow the system language"
        )
        preferences.save(.es)
        expect(values[key] == "es", "Saving Spanish must persist its language code")
        expect(preferences.load() == .es, "The persisted Spanish preference must reload")
        preferences.save(.en)
        expect(preferences.load() == .en, "The persisted English preference must reload")
    }

    private static func assertLocalized(
        _ source: String,
        english expectedEnglish: String,
        spanish expectedSpanish: String,
        englishTranslations: [String: String],
        spanishTranslations: [String: String]
    ) {
        let actualEnglish = AppLanguage.en.localizedMessage(source, using: englishTranslations)
        let actualSpanish = AppLanguage.es.localizedMessage(source, using: spanishTranslations)
        expect(
            actualEnglish == expectedEnglish,
            "English mismatch for '\(source)': '\(actualEnglish)' != '\(expectedEnglish)'"
        )
        expect(
            actualSpanish == expectedSpanish,
            "Spanish mismatch for '\(source)': '\(actualSpanish)' != '\(expectedSpanish)'"
        )
    }

    private static func loadTranslations(languageCode: String) throws -> [String: String] {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceURL = projectURL
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(languageCode).lproj")
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: resourceURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let translations = propertyList as? [String: String] else {
            throw LocalizationCheckError.invalidStringsFile(resourceURL.path)
        }
        return translations
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) {
        guard condition() else { preconditionFailure(message()) }
    }
}

private enum LocalizationCheckError: Error {
    case invalidStringsFile(String)
}
