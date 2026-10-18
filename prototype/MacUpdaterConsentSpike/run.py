#!/usr/bin/env python3
"""Real AppKit + unmodified Sparkle, isolated bundle, ephemeral fixture keys only."""
import argparse
import functools
import hashlib
import http.server
import json
import os
import pathlib
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
VERSION = '2.10.0'
DIGEST = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))


def run(*args):
    result = subprocess.run(args, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout


class FixtureRun:
    """Own an isolated run and publish failure evidence even when cleanup fails."""

    def __init__(self, output):
        self.output = pathlib.Path(output)
        self.root = None
        self.secrets = None
        self.process = None
        self.requests = []
        self.results = []
        self.cleanup_errors = []
        self._servers = []

    def __enter__(self):
        try:
            self.root = pathlib.Path(tempfile.mkdtemp(prefix='estrobo-consent-spike-'))
            print(f'Artifacts: {self.root}', flush=True)
            (self.root / 'events.log').touch()
            (self.root / 'stdout.log').touch()
            self.secrets = pathlib.Path(tempfile.mkdtemp(prefix='estrobo-consent-fixture-secrets-'))
            return self
        except BaseException as error:
            self._finish(error)
            raise

    def __exit__(self, error_type, error, traceback):
        self._finish(error)
        if error is None and self.cleanup_errors:
            raise RuntimeError('Fixture cleanup failed: ' + '; '.join(self.cleanup_errors))
        return False

    def start_server(self, handler):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        entry = {'server': server, 'thread': None}
        self._servers.append(entry)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        entry['thread'] = thread
        thread.start()
        return server

    def _attempt(self, label, action):
        try:
            action()
            return True
        except ProcessLookupError:
            return True  # The fixture exited between checking it and signaling it.
        except BaseException as error:
            self.cleanup_errors.append(f'{label}: {type(error).__name__}: {error}')
            return False

    def _stop_process(self):
        if self.process is None or self.process.poll() is not None:
            return
        terminated = self._attempt('terminate fixture process', self.process.terminate)
        if terminated and self._attempt('wait for fixture termination', lambda: self.process.wait(timeout=3)):
            return
        # Failure to terminate or a timeout must not block secret/evidence cleanup.
        if self.process.poll() is None:
            self._attempt('kill fixture process', self.process.kill)
            self._attempt('wait for killed fixture process', lambda: self.process.wait(timeout=3))

    def _stop_recorded_processes(self):
        if self.root is None or not (self.root / 'events.log').exists():
            return
        for pid in set(re.findall(r'pid=(\d+)', (self.root / 'events.log').read_text())):
            live = subprocess.run(['ps', '-p', pid, '-o', 'command='], capture_output=True, text=True, timeout=2)
            expected = (self.root / 'installed' / 'ConsentSpike.app' / 'Contents' / 'MacOS' / 'ConsentSpike').resolve()
            command = live.stdout.strip().split(maxsplit=1)
            if expected.is_relative_to(self.root.resolve()) and command and pathlib.Path(command[0]).resolve() == expected:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except ProcessLookupError:
                    pass  # A fixture that exited after the identity check needs no signal.

    def _finish(self, error):
        # Each operation is independent: one process/server failure cannot skip
        # the other resources, private-key deletion, or the failure report.
        self._attempt('stop fixture process', self._stop_process)
        self._attempt('stop recorded fixture processes', self._stop_recorded_processes)
        for entry in self._servers:
            server, thread = entry['server'], entry['thread']
            if thread is not None:
                self._attempt('shutdown fixture server', lambda: server.shutdown() if thread.is_alive() else None)
            self._attempt('close fixture server socket', server.server_close)
        if self.secrets is not None:
            # Delete the known private file independently even if removing the
            # enclosing directory encounters an unrelated filesystem failure.
            self._attempt('delete fixture private key', lambda: (self.secrets / 'fixture-private-key').unlink(missing_ok=True))
            self._attempt('remove fixture secrets directory', lambda: shutil.rmtree(self.secrets))

        if self.root is not None:
            self._attempt('write request evidence', lambda: (self.root / 'requests.json').write_text(json.dumps(self.requests, indent=2)))
        output_ready = self._attempt('create evidence output', lambda: self.output.mkdir(parents=True, exist_ok=True))
        if output_ready and self.root is not None:
            for name in ('events.log', 'requests.json', 'stdout.log', 'artifact.json'):
                if (self.root / name).exists():
                    self._attempt('copy ' + name, lambda name=name: shutil.copy2(self.root / name, self.output / name))

        if output_ready and self.root is not None and (self.root / 'ui').exists():
            self._attempt('copy visible UI evidence', lambda: shutil.copytree(self.root / 'ui', self.output / 'ui', dirs_exist_ok=True))

        def result():
            failure = f'{type(error).__name__}: {error}' if error is not None else None
            if failure is None and self.cleanup_errors:
                failure = 'Fixture cleanup failed: ' + '; '.join(self.cleanup_errors)
            return json.dumps({'passed': error is None and not self.cleanup_errors, 'failure': failure, 'cleanup_errors': self.cleanup_errors, 'cases': self.results}, indent=2)

        if self.root is not None:
            self._attempt('write artifact results', lambda: (self.root / 'results.json').write_text(result()))
        if output_ready:
            self._attempt('write output results', lambda: (self.output / 'results.json').write_text(result()))
        # If publishing failed, the artifact copy must also record that failure.
        if self.cleanup_errors and self.root is not None:
            self._attempt('record final cleanup failure', lambda: (self.root / 'results.json').write_text(result()))
        print(f'Evidence: {self.output}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sparkle', type=pathlib.Path, help='Already extracted official Sparkle distribution; default downloads pinned hash')
    parser.add_argument('--output', type=pathlib.Path, required=True, help='Directory for text evidence (no keys or binaries)')
    parser.add_argument('--negative-control', action='store_true', help='Reproduce held ready callback installing on ordinary quit')
    parser.add_argument('--redirect-diagnostic', action='store_true', help='Prove public global URLProtocol cannot guard Sparkle feed redirects')
    parser.add_argument('--ui-events', action='store_true', help='Drive visible controls through native AppKit mouse/key events')
    args = parser.parse_args()
    assert not (args.negative_control and args.redirect_diagnostic)
    with FixtureRun(args.output) as fixture:
        root = fixture.root
        secrets = fixture.secrets
        (root / 'mode').write_text('baseline' if args.negative_control else 'redirect' if args.redirect_diagnostic else 'ui' if args.ui_events else 'cache')
        requests = fixture.requests
        results = fixture.results
        slow_download = False
        process = None

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, fmt, *values):
                requests.append({'host': self.headers.get('Host'), 'message': fmt % values})

            def do_GET(self):
                if args.redirect_diagnostic and self.path == '/appcast.xml':
                    self.send_response(302)
                    self.send_header('Location', forbidden_base + '/redirected.xml')
                    self.end_headers()
                    return
                return super().do_GET()

            def copyfile(self, source, outputfile):
                if not slow_download or not self.path.startswith('/update.dmg'):
                    return super().copyfile(source, outputfile)
                try:
                    while chunk := source.read(8192):
                        outputfile.write(chunk)
                        outputfile.flush()
                        time.sleep(.02)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        server = fixture.start_server(functools.partial(Handler, directory=str(root)))
        base = f'http://127.0.0.1:{server.server_port}'
        class ForbiddenOriginHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, fmt, *values):
                requests.append({'host': self.headers.get('Host'), 'forbidden_origin': True, 'message': fmt % values})
        forbidden_server = fixture.start_server(functools.partial(ForbiddenOriginHandler, directory=str(root)))
        forbidden_base = f'http://localhost:{forbidden_server.server_port}'
        command_id = 0
        start_offset = 0

        def command(action):
            nonlocal command_id
            command_id += 1
            temporary = root / 'command.tmp'
            temporary.write_text(f'{command_id} {action}')
            temporary.replace(root / 'command')

        def events():
            return (root / 'events.log').read_text()[start_offset:]

        def wait_for(event, timeout=20):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if event in events():
                    return
                time.sleep(.05)
            raise AssertionError(f'Timed out waiting for {event}\n{events()}')

        def begin(name):
            nonlocal start_offset
            start_offset = len((root / 'events.log').read_text())
            with (root / 'events.log').open('a') as file:
                file.write(f'CASE {name}\n')
            print(name, flush=True)

        def passed(name, **evidence):
            results.append({'case': name, 'passed': True, **evidence})
            print(f'PASS {name}', flush=True)

        def version():
            return plistlib.loads((app / 'Contents' / 'Info.plist').read_bytes())['CFBundleVersion']

        def launch():
            nonlocal process
            (root / 'command').unlink(missing_ok=True)
            process = subprocess.Popen([str(app / 'Contents' / 'MacOS' / 'ConsentSpike'), str(root)], env=ENV, stdout=(root / 'stdout.log').open('a'), stderr=subprocess.STDOUT)
            fixture.process = process
            wait_for('launched')

        def quit_and_check(action='quit', expected='1'):
            command(action)
            process.wait(timeout=15)
            # The negative control replaces promptly; allow enough time to observe replacement.
            time.sleep(2)
            assert version() == expected, f'{action}: expected build {expected}, found {version()}'

        def archive_requests():
            return sum('/update.dmg' in entry['message'] for entry in requests)

        sparkle = args.sparkle
        if sparkle is None:
            dependency_archive = root / 'Sparkle.tar.xz'
            urllib.request.urlretrieve(f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz', dependency_archive)
            assert hashlib.sha256(dependency_archive.read_bytes()).hexdigest() == DIGEST, 'Sparkle distribution hash mismatch'
            sparkle = root / 'dependency'
            sparkle.mkdir()
            run('tar', '-xf', str(dependency_archive), '-C', str(sparkle))
        else:
            assert plistlib.loads((sparkle / 'Sparkle.framework' / 'Resources' / 'Info.plist').read_bytes())['CFBundleShortVersionString'] == VERSION
        run('xcrun', 'swift', str(HERE / 'fixture-key.swift'), str(secrets))
        private_key = secrets / 'fixture-private-key'
        private_key.chmod(0o600)
        public_key = (secrets / 'fixture-public-key').read_text()
        binary = root / 'ConsentSpike'
        run('xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=13.0', '-F' + str(sparkle), '-framework', 'Cocoa', '-framework', 'Sparkle', '-Wl,-rpath,@executable_path/../Frameworks', str(HERE / 'main.m'), '-o', str(binary))
        bundle_id = 'mx.loo.estrobo.consent-spike.' + root.name.split('-')[-1]
        for build in (1, 2):
            bundle = root / f'build{build}' / 'ConsentSpike.app'
            (bundle / 'Contents' / 'MacOS').mkdir(parents=True)
            (bundle / 'Contents' / 'Frameworks').mkdir()
            shutil.copy2(binary, bundle / 'Contents' / 'MacOS' / 'ConsentSpike')
            run('ditto', str(sparkle / 'Sparkle.framework'), str(bundle / 'Contents' / 'Frameworks' / 'Sparkle.framework'))
            info = {'CFBundleIdentifier': bundle_id, 'CFBundleName': 'ConsentSpike', 'CFBundleExecutable': 'ConsentSpike', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': str(build), 'CFBundleShortVersionString': f'0.0.{build}', 'LSMinimumSystemVersion': '13.0', 'SUPublicEDKey': public_key, 'SUFeedURL': base + '/appcast.xml', 'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False, 'SUEnableInstallerLauncherService': False, 'SUEnableSystemProfiling': False, 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True, 'SUSignedFeedFailureExpirationInterval': 0, 'ConsentSpikeRoot': str(root)}
            (bundle / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info))
            run('codesign', '--force', '--sign', '-', str(bundle))
        archive = root / 'update.dmg'
        run('hdiutil', 'create', '-quiet', '-volname', 'ConsentSpike', '-srcfolder', str(root / 'build2'), '-format', 'UDZO', str(archive))
        archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
        signature = run(str(sparkle / 'bin' / 'sign_update'), '--ed-key-file', str(private_key), '-p', str(archive)).strip()
        verification = run(str(sparkle / 'bin' / 'sign_update'), '--ed-key-file', str(private_key), '--verify', str(archive), signature)
        feed = f'<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated Consent Spike</title><item><title>Fixture build 2</title><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><enclosure url="{base}/update.dmg" sparkle:version="2" sparkle:shortVersionString="0.0.2" sparkle:edSignature="{signature}" length="{archive.stat().st_size}" type="application/octet-stream"/></item></channel></rss>'

        def publish_feed(text=feed):
            (root / 'appcast.xml').write_text(text)
            run(str(sparkle / 'bin' / 'sign_update'), '--ed-key-file', str(private_key), str(root / 'appcast.xml'))

        publish_feed()
        (root / 'offer.plist').write_bytes(plistlib.dumps({'build': '2', 'url': base + '/update.dmg', 'length': archive.stat().st_size, 'signature': signature}))
        app = root / 'installed' / 'ConsentSpike.app'
        run('ditto', str(root / 'build1' / 'ConsentSpike.app'), str(app))
        if args.ui_events:
            def click(identifier):
                command('mouse:' + identifier)
                wait_for('ui-action ' + identifier)

            begin('visible-download-ordinary-command-q')
            launch()
            wait_for('ui-controls-ready')
            click('download')
            wait_for('cache-complete-without-consent')
            assert hashlib.sha256((root / 'cache.dmg').read_bytes()).hexdigest() == archive_hash
            quit_and_check('key:quit')
            passed('visible-download-ordinary-command-q', installed_build='1')

            begin('visible-process-restart-close-window-button')
            launch()
            wait_for('ui-controls-ready')
            assert version() == '1'
            quit_and_check('mouse:window-close')
            wait_for('last-window-closed')
            passed('visible-process-restart-close-window-button', installed_build='1')

            begin('visible-cancel-transfer-and-retry')
            launch()
            slow_download = True
            click('download')
            wait_for('cache-download-started')
            click('cancel')
            wait_for('cache-download-cancelled-or-failed')
            assert not (root / 'cache.dmg').exists()
            slow_download = False
            click('download')
            wait_for('cache-complete-without-consent')
            assert hashlib.sha256((root / 'cache.dmg').read_bytes()).hexdigest() == archive_hash
            quit_and_check('key:quit')
            passed('visible-cancel-transfer-and-retry', installed_build='1')

            begin('visible-cancel-remains-usable-during-preparation')
            launch()
            click('confirm-hold')
            wait_for('ready-held-after-consent')
            click('cancel')
            wait_for('attempt-dismissed-window-restored')
            wait_for('ui-cycle-finished')
            quit_and_check('key:quit')
            passed('visible-cancel-remains-usable-during-preparation', installed_build='1')

            begin('visible-appkit-veto-before-preparation')
            launch()
            click('block')
            click('confirm-hold')
            wait_for('appkit-veto-consent-invalidated')
            assert 'sparkle-cache-copy-started' not in events()
            assert process.poll() is None
            click('unblock')
            quit_and_check('key:quit')
            passed('visible-appkit-veto-before-preparation', installed_build='1')

            begin('visible-final-appkit-veto-cancels-prepared-installer')
            launch()
            click('confirm-hold')
            wait_for('ready-held-after-consent')
            click('veto')
            click('continue')
            wait_for('appkit-veto-consent-invalidated')
            wait_for('attempt-dismissed-window-restored')
            wait_for('ui-cycle-finished')
            assert process.poll() is None and version() == '1'
            click('unblock')
            quit_and_check('key:quit')
            passed('visible-final-appkit-veto-cancels-prepared-installer', installed_build='1')

            begin('visible-command-q-cancels-prepared-attempt')
            launch()
            click('confirm-hold')
            wait_for('ready-held-after-consent')
            quit_and_check('key:quit')
            wait_for('ordinary-quit-awaits-installer-cancellation')
            passed('visible-command-q-cancels-prepared-attempt', installed_build='1')

            begin('visible-new-unsafe-work-invalidates-consent')
            launch()
            click('confirm-hold')
            wait_for('ready-held-after-consent')
            click('block')
            wait_for('attempt-dismissed-window-restored')
            wait_for('ui-cycle-finished')
            assert process.poll() is None and version() == '1'
            click('unblock')
            quit_and_check('key:quit')
            passed('visible-new-unsafe-work-invalidates-consent', installed_build='1')

            begin('visible-fresh-signed-offer-change-rejected')
            publish_feed(feed.replace('sparkle:version="2"', 'sparkle:version="3"'))
            launch()
            click('confirm')
            wait_for('fresh-offer-rejected')
            wait_for('ui-cycle-finished')
            assert 'sparkle-cache-copy-started' not in events()
            quit_and_check('key:quit')
            publish_feed()
            passed('visible-fresh-signed-offer-change-rejected', installed_build='1')

            begin('visible-cache-eviction-fails-closed')
            launch()
            requests_before = archive_requests()
            click('confirm-evict')
            wait_for('strict-cache-only lookup=NO')
            wait_for('ui-cycle-finished')
            assert archive_requests() == requests_before
            quit_and_check('key:quit')
            passed('visible-cache-eviction-fails-closed', installed_build='1', additional_archive_requests=0)

            begin('visible-tampered-cache-rejected-by-sparkle')
            cache = bytearray((root / 'cache.dmg').read_bytes())
            cache[len(cache) // 2] ^= 1
            (root / 'cache.dmg').write_bytes(cache)
            launch()
            click('confirm')
            wait_for('ui-cycle-finished')
            assert 'error ' in events() and 'ready-after-consent' not in events()
            quit_and_check('key:quit')
            shutil.copy2(archive, root / 'cache.dmg')
            passed('visible-tampered-cache-rejected-by-sparkle', installed_build='1')

            begin('visible-cancel-and-retry-installs-exact-cache-and-relaunches')
            launch()
            click('confirm-hold')
            wait_for('ready-held-after-consent')
            click('cancel')
            wait_for('ui-cycle-finished')
            assert version() == '1' and process.poll() is None
            requests_before = archive_requests()
            click('confirm')
            wait_for('appkit-final-commit-accepted')
            wait_for('installing-approved-offer')
            process.wait(timeout=15)
            wait_for('build=2 ui-controls-ready')
            wait_for('build=2 launched')
            assert version() == '2'
            assert archive_requests() == requests_before
            passed('visible-cancel-and-retry-installs-exact-cache-and-relaunches', installed_build='2', additional_archive_requests=0, archive_sha256=archive_hash)
            command('key:quit')
            wait_for('build=2 ordinary-termination-allowed')
        elif args.redirect_diagnostic:
            shutil.copy2(root / 'appcast.xml', root / 'redirected.xml')
            begin('forbidden-feed-redirect-bypasses-global-urlprotocol')
            launch()
            command('download')
            wait_for('cache-complete-without-consent')
            command('confirm-cancel')
            wait_for('ready-held-after-consent')
            assert any(entry.get('forbidden_origin') for entry in requests), 'forbidden origin was not requested'
            assert 'global-protocol-consulted' in events(), 'global protocol was not registered early enough'
            assert 'global-protocol-rejected-forbidden-origin' not in events(), 'guard unexpectedly intercepted Sparkle session'
            wait_for('attempt-dismissed-window-restored')
            quit_and_check()
            passed('forbidden-feed-redirect-bypasses-global-urlprotocol', forbidden_origin_fetched=True, network_gate_passed=False, installed_build='1')
        elif args.negative_control:
            begin('negative-control-held-ready-normal-quit')
            launch()
            command('download')
            wait_for('prepared-without-consent')
            assert version() == '1'
            quit_and_check(expected='2')
            passed('negative-control-held-ready-normal-quit', observed_unconsented_build='2')
        else:
            begin('completed-download-normal-quit')
            launch()
            command('download')
            wait_for('cache-complete-without-consent')
            assert hashlib.sha256((root / 'cache.dmg').read_bytes()).hexdigest() == archive_hash
            assert 'extracting-after-consent' not in events()
            quit_and_check()
            passed('completed-download-normal-quit', installed_build='1', cache_sha256=archive_hash)

            begin('process-restart-and-last-window-close')
            launch()
            assert version() == '1'
            assert hashlib.sha256((root / 'cache.dmg').read_bytes()).hexdigest() == archive_hash
            quit_and_check('last-window')
            passed('process-restart-and-last-window-close', installed_build='1')

            begin('appkit-veto-invalidates-consent')
            launch()
            command('block')
            wait_for('blocked')
            command('confirm')
            wait_for('appkit-veto-consent-invalidated')
            assert process.poll() is None and version() == '1'
            assert 'sparkle-cache-copy-started' not in events()
            command('unblock')
            wait_for('unblocked')
            quit_and_check()
            passed('appkit-veto-invalidates-consent', installed_build='1')

            begin('cancel-download-and-retry')
            launch()
            slow_download = True
            command('download')
            wait_for('cache-download-started')
            command('cancel')
            wait_for('cache-download-cancelled-or-failed')
            assert not (root / 'cache.dmg').exists()
            slow_download = False
            command('download')
            wait_for('cache-complete-without-consent')
            assert hashlib.sha256((root / 'cache.dmg').read_bytes()).hexdigest() == archive_hash
            quit_and_check()
            passed('cancel-download-and-retry', installed_build='1')

            for action, name in [('cancel', 'cancel-prepared-authorized-attempt'), ('block', 'new-unsafe-work-invalidates-consent'), ('quit', 'ordinary-quit-cancels-prepared-attempt')]:
                begin(name)
                launch()
                command('confirm-' + action)
                wait_for('ready-held-after-consent')
                assert version() == '1'
                if action == 'quit':
                    process.wait(timeout=15)
                    time.sleep(2)
                    assert version() == '1'
                else:
                    wait_for('attempt-dismissed-window-restored')
                    assert process.poll() is None and version() == '1'
                    if action == 'block':
                        command('unblock')
                        wait_for('unblocked')
                    quit_and_check()
                passed(name, installed_build='1')

            begin('fresh-signed-offer-change-invalidates-consent')
            publish_feed(feed.replace('sparkle:version="2"', 'sparkle:version="3"'))
            launch()
            command('confirm')
            wait_for('fresh-offer-rejected')
            wait_for('attempt-dismissed-window-restored')
            assert 'sparkle-cache-copy-started' not in events()
            quit_and_check()
            publish_feed()
            passed('fresh-signed-offer-change-invalidates-consent', installed_build='1')

            begin('cache-eviction-fails-closed')
            launch()
            requests_before = archive_requests()
            command('confirm-evict')
            wait_for('strict-cache-only lookup=NO')
            wait_for('attempt-dismissed-window-restored')
            assert archive_requests() == requests_before, 'cache miss silently fetched archive from network'
            quit_and_check()
            passed('cache-eviction-fails-closed', installed_build='1', additional_archive_requests=0)

            begin('tampered-cache-rejected-by-sparkle')
            cache = bytearray((root / 'cache.dmg').read_bytes())
            cache[len(cache) // 2] ^= 1
            (root / 'cache.dmg').write_bytes(cache)
            launch()
            command('confirm')
            wait_for('attempt-dismissed-window-restored')
            assert 'error ' in events() and 'ready-after-consent' not in events()
            quit_and_check()
            shutil.copy2(archive, root / 'cache.dmg')
            passed('tampered-cache-rejected-by-sparkle', installed_build='1')

            begin('confirm-exact-cache-install-and-relaunch')
            launch()
            requests_before = archive_requests()
            command('confirm')
            wait_for('installing-approved-offer')
            process.wait(timeout=15)
            wait_for('build=2 launched')
            assert version() == '2'
            assert 'fresh-signed-offer-matches' in events()
            assert 'strict-cache-only lookup=YES' in events()
            assert archive_requests() == requests_before, 'approved installation redownloaded the archive'
            passed('confirm-exact-cache-install-and-relaunch', installed_build='2', additional_archive_requests=0, archive_sha256=archive_hash)
            command('quit')
            wait_for('build=2 ordinary-termination-allowed')
        (root / 'artifact.json').write_text(json.dumps({'sparkle_version': VERSION, 'sparkle_distribution_sha256': DIGEST, 'bundle_identifier': bundle_id, 'dmg_sha256': archive_hash, 'dmg_length': archive.stat().st_size, 'eddsa_signature': signature, 'official_signature_verification': {'exit': 0, 'output': verification.strip()}, 'os': run('sw_vers').strip(), 'toolchain': run('xcrun', 'clang', '--version').strip()}, indent=2))


if __name__ == '__main__':
    main()
