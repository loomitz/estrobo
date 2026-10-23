import XCTest
import CryptoKit

/// Runs only in a fresh GitHub-hosted macOS user. Neither release is rebuilt,
/// re-signed, instrumented, given launch arguments, or pointed at another feed.
@MainActor
final class OfficialUpdaterQualificationTests: XCTestCase {
    private let productID = "mx.loo.estrobo"
    private var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("estrobo-qualification") }
    private var app: XCUIApplication { XCUIApplication(bundleIdentifier: productID) }
    private var container: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/\(productID)/Data") }
    private var preferenceFile: URL { container.appendingPathComponent("Library/Preferences/\(productID).plist") }
    private var cache: URL { container.appendingPathComponent("Library/Caches/EstroboAssistedUpdates") }
    private var evidence: URL { root.appendingPathComponent("evidence") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard NSUserName() == "runner", FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              FileManager.default.fileExists(atPath: root.appendingPathComponent("plan.json").path) else {
            throw XCTSkip("Disposable hosted qualification user required; user=\(NSUserName()), home=\(FileManager.default.homeDirectoryForCurrentUser.path)")
        }
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        addUIInterruptionMonitor(withDescription: "Expected Bluetooth prompt in a VM") { alert in
            let bluetoothText = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Bluetooth"))
            guard alert.label.localizedCaseInsensitiveContains("Bluetooth") || bluetoothText.count > 0 else { return false }
            for label in ["Don’t Allow", "Don't Allow", "No permitir"] where alert.buttons[label].exists {
                alert.buttons[label].click(); return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        guard NSUserName() == "runner", FileManager.default.fileExists(atPath: root.appendingPathComponent("plan.json").path),
              let run = testRun, run.failureCount > 0 else { return }
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: evidence.appendingPathComponent("failure.png"))
        try JSONSerialization.data(withJSONObject: ["passed": false, "failureCount": run.failureCount,
                                                    "appHierarchy": app.debugDescription], options: .prettyPrinted)
            .write(to: evidence.appendingPathComponent("failure.json"))
    }

    private func command(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        return String(decoding: data, as: UTF8.self)
    }

    private func wait(_ description: String, seconds: TimeInterval = 120, _ check: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in check() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: seconds), .completed, description + "\n" + app.debugDescription)
    }

    private func capture(_ name: String) throws {
        let screenshot = app.screenshot()
        try screenshot.pngRepresentation.write(to: evidence.appendingPathComponent(name + ".png"))
    }

    private func installedBuild() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/Applications/estrobo.app/Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleVersion"] as? String
    }

    private func productHashes() throws -> [String: String] {
        _ = try command("/usr/bin/defaults", ["export", preferenceFile.deletingPathExtension().path, root.appendingPathComponent("preferences-snapshot.plist").path])
        let data = try Data(contentsOf: root.appendingPathComponent("preferences-snapshot.plist"))
        let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNil(values["GodoxMacControlPrototype.savedRadios.v2"], "The release app must migrate the synthetic legacy credential to Keychain")
        XCTAssertNotNil(values["GodoxMacControlPrototype.savedRadios.v3"])
        var result: [String: String] = [:]
        for (key, value) in values where key.hasPrefix("GodoxMacControlPrototype.") || key == "Estrobo.appearance.v1" {
            let bytes = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
            result[key] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        if let preferences = values["macOS.assistedUpdates.preferences.v1"] as? Data,
           let state = try JSONSerialization.jsonObject(with: preferences) as? [String: Any] {
            XCTAssertEqual(state["automaticChecks"] as? Bool, false)
            XCTAssertEqual(state["automaticDownloads"] as? Bool, false)
        }
        return result
    }

    private func assertRadioHydrates(_ screenshot: String) throws {
        app.activate()
        let updates = app.windows["Actualizaciones"]
        if updates.exists { updates.buttons[XCUIIdentifierCloseWindow].click() }
        let saved = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@",
                                                     "Ver transmisores…", "Transmisores guardados…")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15), app.debugDescription)
        // A real click activates XCTest's interruption handler if macOS is
        // displaying its Bluetooth permission dialog; existence queries do not.
        saved.click()
        XCTAssertTrue(app.staticTexts["Godox QA oficial"].firstMatch.waitForExistence(timeout: 15),
                      "A saved radio is exposed only after the release app reads its credential from Keychain")
        try capture(screenshot)
        app.buttons["Listo"].firstMatch.click()
    }

    private func openUpdates() {
        app.activate()
        app.menuBars.menuBarItems.element(boundBy: 1).click()
        let check = app.menuItems.matching(identifier: "updates.menuCheck").firstMatch
        if check.exists { check.click() }
        else { app.menuItems.matching(NSPredicate(format: "label CONTAINS[cd] %@", "actualizaciones")).firstMatch.click() }
        XCTAssertTrue(app.buttons["updates.check"].waitForExistence(timeout: 20))
    }

    private func archiveHash() throws -> String {
        let descriptor = try Data(contentsOf: cache.appendingPathComponent("download.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: descriptor) as? [String: Any])
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent("download-descriptor.json"))
        let archives = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).filter { $0.pathExtension == "dmg" }
        XCTAssertEqual(archives.count, 1)
        let bytes = try Data(contentsOf: XCTUnwrap(archives.first))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func testOfficialFiveToSixCancellationRecoveryAndRelaunch() throws {
        let plan = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("plan.json"))) as? [String: Any])
        XCTAssertEqual(installedBuild(), "5")
        // Bootstrap creates the sandbox through the real app. Seed synthetic
        // v2 data only after it exits; the app itself performs Keychain migration.
        app.launch(); XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20)); app.terminate()
        _ = try command("/usr/bin/defaults", ["import", preferenceFile.deletingPathExtension().path, root.appendingPathComponent("synthetic-preferences.plist").path])
        app.launch()
        try assertRadioHydrates("01-build5-keychain")
        let before = try productHashes()
        XCTAssertGreaterThanOrEqual(before.count, 5)
        openUpdates()
        wait("The official signed feed must offer build 6") { self.app.staticTexts["updates.status"].label == "Hay una actualización disponible." }
        try capture("02-official-offer")
        app.buttons["updates.download"].click()
        wait("The exact public GitHub DMG must finish downloading", seconds: 180) { self.app.buttons["updates.install"].exists && self.app.buttons["updates.install"].isEnabled }
        let downloaded = try archiveHash()
        XCTAssertEqual(downloaded, plan["dmgSHA256"] as? String)
        app.buttons["updates.install"].click()
        XCTAssertTrue(app.buttons["updates.cancelConfirmation"].waitForExistence(timeout: 10))
        app.buttons["updates.cancelConfirmation"].click()
        try capture("03-cancelled")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
        XCTAssertEqual(installedBuild(), "5", "Normal quit must not silently install")
        app.launch(); openUpdates()
        wait("The verified download must recover after relaunch") { self.app.buttons["updates.install"].exists && self.app.buttons["updates.install"].isEnabled }
        XCTAssertEqual(try archiveHash(), downloaded)
        let oldPID = try command("/usr/bin/pgrep", ["-x", "estrobo"]).trimmingCharacters(in: .whitespacesAndNewlines)
        app.buttons["updates.install"].click()
        XCTAssertTrue(app.buttons["updates.confirm"].waitForExistence(timeout: 10)); app.buttons["updates.confirm"].click()
        wait("Sparkle must replace the application with official build 6", seconds: 180) { self.installedBuild() == "6" }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "The installer must relaunch the real app")
        let newPID = try command("/usr/bin/pgrep", ["-x", "estrobo"]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(oldPID, newPID)
        try assertRadioHydrates("04-build6-keychain")
        XCTAssertEqual(try productHashes(), before)
        openUpdates()
        wait("The installed app must recognize build 6 as current") { self.app.staticTexts["updates.status"].label == "Estrobo está actualizado." }
        try capture("05-build6-current")
        let result: [String: Any] = ["passed": true, "installedBuild": "6", "bundleIdentifier": productID,
            "feedURL": "https://estrobo.app/updates/macos/appcast.xml", "archiveSHA256": downloaded,
            "normalQuitKeptBuild5": true, "verifiedDownloadRecovered": true, "oldPID": oldPID, "newPID": newPID,
            "productDataHashes": before, "syntheticKeychainHydratedInBothReleases": true,
            "automaticChecks": false, "automaticDownloads": false,
            "scope": "Hosted macOS native UI; browser quarantine, physical Bluetooth and macOS 13 remain separate gates"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent("result.json"))
    }
}
