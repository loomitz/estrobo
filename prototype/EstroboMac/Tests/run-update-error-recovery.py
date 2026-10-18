#!/usr/bin/env python3
"""Compile a narrow native check; isolate the app domain and all HTTP/files."""
import base64
import http.server
import os
import pathlib
import platform
import plistlib
import subprocess
import tempfile
import threading
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE.parent / 'Sources'
SPARKLE = pathlib.Path(os.environ.get('SPARKLE_DIR', HERE.parents[2] / '.build/Sparkle/2.10.0'))
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))


def main():
    with tempfile.TemporaryDirectory(prefix='estrobo-error-recovery-') as temporary:
        root = pathlib.Path(temporary)
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_HEAD(self):
                self.send_response(200)
                self.end_headers()

            def do_GET(self):
                (root / 'started').touch()
                deadline = time.monotonic() + 15
                while not (root / 'release').exists() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.send_response(503)
                self.send_header('Content-Length', '0')
                self.end_headers()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        identifier = 'mx.loo.estrobo.tests.recovery.' + uuid.uuid4().hex
        try:
            app = root / 'Recovery.app'
            executable = app / 'Contents/MacOS/Recovery'
            executable.parent.mkdir(parents=True)
            info = {'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'Recovery',
                    'CFBundleVersion': '4', 'CFBundleShortVersionString': '0.1.0', 'EstroboUpdateChannel': 'beta',
                    'SUPublicEDKey': base64.b64encode(bytes(32)).decode(), 'SUEnableDownloaderService': False,
                    'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
                    'SUSignedFeedFailureExpirationInterval': 0, 'SUEnableAutomaticChecks': False,
                    'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False}
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-warnings-as-errors', '-D', 'ESTROBO_UPDATER_TESTING',
                            '-target', platform.machine() + '-apple-macosx13.0', '-framework', 'AppKit', '-framework', 'Combine',
                            '-F', str(SPARKLE), '-framework', 'Sparkle',
                            *[str(SOURCES / name) for name in ('UpdateService.swift', 'UpdateHTTPClient.swift', 'UpdateInstallationLifecycle.swift', 'SparkleUpdateService.swift')],
                            str(HERE / 'UpdateErrorRecoveryCheck.swift'), '-o', str(executable)], check=True, env=ENV)
            subprocess.run([str(executable), str(root), f'http://127.0.0.1:{server.server_port}/appcast.xml'],
                           check=True, timeout=90, env=dict(ENV, DYLD_FRAMEWORK_PATH=str(SPARKLE)))
        finally:
            (root / 'release').touch()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
            # Also remove the isolated Sparkle host domain after a native crash
            # or timeout, when the Swift defer cannot run.
            subprocess.run(['/usr/bin/defaults', 'delete', identifier], capture_output=True)


if __name__ == '__main__':
    main()
