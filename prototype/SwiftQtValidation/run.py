"""CI driver. All builds/downloads are under this experiment or RUNNER_TEMP."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
from stage import stage, HERE, STAGE, BASELINE

# Hosted Windows consoles may default to CP1252; Swift logs contain Unicode.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

RESULTS = HERE / "_results"
QT_URL = "https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz"
QT_SHA256 = "56001b905601bb9023d399f3ba780d7fa940f3e4861e496a7c490331f49e0b80"
results = {"baseline": BASELINE, "platform": platform.platform(), "python": sys.version, "steps": [], "status": "running"}

def save():
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")

def run(name, command, cwd=None, timeout=900, env=None):
    print(json.dumps({"step": name, "command": [str(v) for v in command], "cwd": str(cwd or HERE)}), flush=True)
    started = time.monotonic()
    try:
        result = subprocess.run([str(v) for v in command], cwd=cwd or HERE, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        output = result.stdout.decode("utf-8", errors="replace")
        code = result.returncode
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"").decode("utf-8", errors="replace")
        code = -999
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{name}.log").write_text(output, encoding="utf-8")
    print(output, flush=True)
    results["steps"].append({"name": name, "exit_code": code, "seconds": round(time.monotonic() - started, 2), "log": f"{name}.log"})
    save()
    if code:
        raise RuntimeError(f"{name} failed: {code}")
    return output.strip()

def main():
    save()
    stage()
    run("swift-version", ["swift", "--version"])
    run("cmake-version", ["cmake", "--version"])
    # No filters or exclusions: exercise the baseline's entire two-file Core suite.
    run("core-tests", ["swift", "test", "--package-path", STAGE, "--jobs", "4"], timeout=900)
    run("engine-build", ["swift", "build", "--package-path", STAGE, "--product", "estrobo-qt-engine", "--jobs", "4"], timeout=900)
    binary_dir = Path(run("swift-bin-path", ["swift", "build", "--package-path", STAGE, "--show-bin-path"]).splitlines()[-1])
    engine = binary_dir / ("estrobo-qt-engine.exe" if os.name == "nt" else "estrobo-qt-engine")
    if not engine.is_file():
        raise RuntimeError(f"Engine missing: {engine}")
    work = Path(os.environ.get("RUNNER_TEMP", str(HERE / "_results"))) / "estrobo-swift-qt"
    if work.exists():
        raise RuntimeError(f"Refusing to overwrite dependency workspace: {work}")
    work.mkdir(parents=True)
    archive = work / "qtbase.tar.xz"
    urllib.request.urlretrieve(QT_URL, archive)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != QT_SHA256:
        raise RuntimeError(f"Qt hash mismatch: {actual}")
    with tarfile.open(archive, "r:xz") as data:
        data.extractall(work, filter="data")
    qt_source = work / "qtbase-everywhere-src-6.8.3"
    qt_build = work / "build"
    qt_install = work / "install"
    run("qt-configure", ["cmake", "-S", qt_source, "-B", qt_build, "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={qt_install}",
        "-DQT_BUILD_EXAMPLES=OFF", "-DQT_BUILD_TESTS=OFF",
        "-DFEATURE_gui=OFF", "-DFEATURE_widgets=OFF", "-DFEATURE_network=OFF",
        "-DFEATURE_sql=OFF", "-DFEATURE_dbus=OFF", "-DFEATURE_testlib=OFF",
        "-DFEATURE_concurrent=OFF"], timeout=300)
    run("qt-build", ["cmake", "--build", qt_build, "--parallel", "4"], timeout=1200)
    run("qt-install", ["cmake", "--install", qt_build], timeout=300)
    harness_build = work / "harness"
    run("bridge-configure", ["cmake", "-S", HERE, "-B", harness_build, "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_PREFIX_PATH={qt_install}"], timeout=120)
    run("bridge-build", ["cmake", "--build", harness_build, "--parallel", "4"], timeout=120)
    harness = harness_build / ("qt-swift-smoke.exe" if os.name == "nt" else "qt-swift-smoke")
    process_env = os.environ.copy()
    process_env["PATH"] = str(qt_install / "bin") + os.pathsep + process_env.get("PATH", "")
    output = run("bridge-runtime", [harness, engine], timeout=50, env=process_env)
    if "QT_SWIFT_BRIDGE_PASS" not in output:
        raise RuntimeError("Missing runtime pass record")
    results["status"] = "passed-synthetic-only"
    save()

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        results["status"] = "failed-or-blocked"
        results["error"] = str(error)
        save()
        raise
