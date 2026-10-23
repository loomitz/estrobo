"""Stage immutable baseline copies; never edit production sources."""
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

BASELINE = "bf98e82637b562fff732ca82d7a92a66fe984d66"
OPENCOMBINE = "8576f0d579b27020beccbccc3ea6844f3ddfc2c2"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
STAGE = HERE / "_stage"
CONDITIONAL_COMBINE = "#if canImport(Combine)\nimport Combine\n#else\nimport OpenCombine\n#endif"

def original(path):
    return subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT).decode("utf-8").replace("\r\n", "\n")

def stage():
    if STAGE.exists():
        raise RuntimeError(f"Refusing to overwrite existing staging directory: {STAGE}")
    STAGE.mkdir()
    changes, evidence = [], {}
    def copy(path, target):
        before = original(path)
        after = before.replace("import Combine", CONDITIONAL_COMBINE)
        if path.endswith("SimulatedRadioTransport.swift"):
            after = after.replace("#if canImport(EstroboCore)", "#if canImport(EstroboCore) && !ESTROBO_CORE_TARGET")
        output = STAGE / target
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(after, encoding="utf-8", newline="\n")
        changes.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=path, tofile=target))
        evidence[path] = {"sha256_original": hashlib.sha256(before.encode()).hexdigest(), "sha256_staged": hashlib.sha256(after.encode()).hexdigest()}
    names = subprocess.check_output(["git", "ls-tree", "--name-only", f"{BASELINE}:Sources/EstroboCore"], cwd=ROOT, text=True).splitlines()
    for name in names:
        if name.endswith(".swift"):
            copy(f"Sources/EstroboCore/{name}", f"Sources/EstroboCore/{name}")
    copy("Sources/EstroboBluetooth/SimulatedRadioTransport.swift", "Sources/EstroboCore/SimulatedRadioTransport.swift")
    for name in ["GodoxSessionControllerTests.swift", "EstroboCoreSmokeTests.swift"]:
        copy(f"Tests/EstroboCoreTests/{name}", f"Tests/EstroboCoreTests/{name}")
    tests = original("Tests/EstroboCoreTests/GodoxSessionControllerTests.swift")
    marker = "@MainActor\nprivate struct Fixture {"
    if tests.count(marker) != 1:
        raise RuntimeError("Fixture extraction anchor changed")
    fixtures = tests[tests.index(marker):].replace("private struct Fixture", "struct Fixture").replace("private final class ", "final class ")
    (STAGE / "Sources/EstroboCore/ExperimentFixtures.swift").write_text("import Foundation\n" + fixtures, encoding="utf-8", newline="\n")
    for name in ["ExperimentRuntime.swift", "EngineMain.swift"]:
        target = STAGE / ("Sources/EstroboCore" if name.startswith("Experiment") else "Sources/Engine") / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text((HERE / name).read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    (STAGE / "Package.swift").write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "EstroboSwiftQtValidation",
    products: [.executable(name: "estrobo-qt-engine", targets: ["Engine"])],
    dependencies: [.package(url: "https://github.com/OpenCombine/OpenCombine.git", revision: "{OPENCOMBINE}")],
    targets: [
        .target(name: "EstroboCore", dependencies: [.product(name: "OpenCombine", package: "OpenCombine")],
            swiftSettings: [.define("ESTROBO_CORE_TARGET")]),
        .executableTarget(name: "Engine", dependencies: ["EstroboCore"]),
        .testTarget(name: "EstroboCoreTests", dependencies: ["EstroboCore", .product(name: "OpenCombine", package: "OpenCombine")])
    ],
    swiftLanguageModes: [.v6]
)
''', encoding="utf-8", newline="\n")
    (STAGE / "adaptation.patch").write_text("".join(changes), encoding="utf-8", newline="\n")
    (STAGE / "source-manifest.json").write_text(json.dumps({"baseline": BASELINE, "opencombine": OPENCOMBINE, "language_mode": "Swift 6 under Swift 6.4.1", "files": evidence, "test_bodies_changed": False, "fixture_extraction": "Tail from private Fixture marker, private helper types made internal; no controller substitution."}, indent=2), encoding="utf-8")
    print(json.dumps({"staged": str(STAGE), "core_files": len(names), "test_bodies_changed": False}))
    return STAGE

if __name__ == "__main__":
    stage()
