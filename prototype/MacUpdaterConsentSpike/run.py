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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sparkle', type=pathlib.Path, help='Already extracted official Sparkle distribution; default downloads pinned hash')
    parser.add_argument('--output', type=pathlib.Path, required=True, help='Directory for text evidence (no keys or binaries)')
    parser.add_argument('--negative-control', action='store_true', help='Reproduce held ready callback installing on ordinary quit')
    parser.add_argument('--redirect-diagnostic', action='store_true', help='Prove public global URLProtocol cannot guard Sparkle feed redirects')
    args = parser.parse_args()
    assert not (args.negative_control and args.redirect_diagnostic)
    root = pathlib.Path(tempfile.mkdtemp(prefix='estrobo-consent-spike-'))
    secrets = pathlib.Path(tempfile.mkdtemp(prefix='estrobo-consent-fixture-secrets-'))
    print(f'Artifacts: {root}', flush=True)
    (root / 'events.log').touch()
    (root / 'stdout.log').touch()
    (root / 'mode').write_text('baseline' if args.negative_control else 'redirect' if args.redirect_diagnostic else 'cache')
    requests = []
    results = []
    slow_download = False
    process = None
    failure = None

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

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(root)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}'
    class ForbiddenOriginHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, fmt, *values):
            requests.append({'host': self.headers.get('Host'), 'forbidden_origin': True, 'message': fmt % values})
    forbidden_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(ForbiddenOriginHandler, directory=str(root)))
    forbidden_base = f'http://localhost:{forbidden_server.server_port}'
    threading.Thread(target=forbidden_server.serve_forever, daemon=True).start()
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
        wait_for('launched')

    def quit_and_check(action='quit', expected='1'):
        command(action)
        process.wait(timeout=15)
        # The negative control replaces promptly; allow enough time to observe replacement.
        time.sleep(2)
        assert version() == expected, f'{action}: expected build {expected}, found {version()}'

    def archive_requests():
        return sum('/update.dmg' in entry['message'] for entry in requests)

    try:
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
        if args.redirect_diagnostic:
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
    except BaseException as error:
        failure = str(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        # Only processes launched by this fixture and recorded with its isolated identity.
        for pid in set(re.findall(r'pid=(\d+)', (root / 'events.log').read_text())):
            try:
                live = subprocess.run(['ps', '-p', pid, '-o', 'command='], capture_output=True, text=True)
                expected = str(root / 'installed' / 'ConsentSpike.app' / 'Contents' / 'MacOS' / 'ConsentSpike')
                if live.stdout.strip().startswith(expected):
                    os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        server.shutdown()
        forbidden_server.shutdown()
        shutil.rmtree(secrets)
        (root / 'requests.json').write_text(json.dumps(requests, indent=2))
        (root / 'results.json').write_text(json.dumps({'passed': failure is None, 'failure': failure, 'cases': results}, indent=2))
        args.output.mkdir(parents=True, exist_ok=True)
        for name in ('events.log', 'requests.json', 'stdout.log', 'results.json', 'artifact.json'):
            if (root / name).exists():
                shutil.copy2(root / name, args.output / name)
        print(f'Evidence: {args.output}', flush=True)


if __name__ == '__main__':
    main()
