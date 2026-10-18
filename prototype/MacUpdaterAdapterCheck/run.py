#!/usr/bin/env python3
"""Exercise the product Swift adapter with real Sparkle and native AppKit events."""
import argparse
import functools
import hashlib
import http.server
import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import time
import urllib.request
import urllib.parse
import uuid
import re
import email.utils
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.dont_write_bytecode = True
REPO = HERE.parents[1]
CONSENT = HERE.parent / 'MacUpdaterConsentSpike'
loader = importlib.util.spec_from_file_location('consent_fixture', CONSENT / 'run.py')
shared = importlib.util.module_from_spec(loader)
loader.loader.exec_module(shared)
FixtureRun, run, ENV = shared.FixtureRun, shared.run, shared.ENV


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--sparkle', type=pathlib.Path)
    parser.add_argument('--sparkle-archive', type=pathlib.Path)
    args = parser.parse_args()
    with FixtureRun(args.output) as fixture:
        root = fixture.root
        delay_feed = False
        head_status = None
        archive_status = None
        archive_redirect = False
        slow_archive = False
        retry_header = '172800'
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, fmt, *values):
                fixture.requests.append({'host': self.headers.get('Host'), 'method': self.command, 'path': self.path, 'message': fmt % values})
            def do_HEAD(self):
                if self.path == '/appcast.xml' and head_status is not None:
                    self.send_response(head_status)
                    self.send_header('Retry-After', retry_header)
                    self.end_headers()
                    return
                super().do_HEAD()
            def do_GET(self):
                if self.path == '/appcast.xml' and delay_feed:
                    (root / 'delayed-feed-started').touch()
                    time.sleep(2)
                if self.path == '/update.dmg' and archive_redirect:
                    self.send_response(302)
                    self.send_header('Location', 'http://example.com/forbidden.dmg')
                    self.end_headers()
                    return
                if self.path == '/update.dmg' and archive_status is not None:
                    body = b'x' * (dmg.stat().st_size + 131072)
                    self.send_response(archive_status)
                    self.send_header('Retry-After', retry_header)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    try: self.wfile.write(body)
                    except (BrokenPipeError, ConnectionResetError): pass
                    return
                super().do_GET()
            def copyfile(self, source, outputfile):
                try:
                    if slow_archive and self.path.endswith('.dmg'):
                        while chunk := source.read(8192):
                            outputfile.write(chunk); outputfile.flush(); time.sleep(.02)
                    else: super().copyfile(source, outputfile)
                except (BrokenPipeError, ConnectionResetError): pass
        server = fixture.start_server(functools.partial(Handler, directory=str(root)))
        base = f'http://127.0.0.1:{server.server_port}'
        sparkle = args.sparkle or REPO / '.build/Sparkle' / shared.VERSION
        dependency = ['python3', str(REPO / 'scripts/macos-updater-artifacts.py'), 'dependency', '--directory', str(sparkle)]
        candidate_archive = args.sparkle_archive
        if candidate_archive is None and (sparkle / 'Sparkle-2.10.0.tar.xz').exists():
            candidate_archive = sparkle / 'Sparkle-2.10.0.tar.xz'
        if candidate_archive is not None:
            dependency += ['--archive', str(candidate_archive)]
        run(*dependency)
        sources = [REPO / 'prototype/EstroboMac/Sources' / name for name in
                   ('UpdateService.swift', 'UpdateHTTPClient.swift', 'UpdateInstallationLifecycle.swift', 'SparkleUpdateService.swift')]
        binary = root / 'ConsentSpike'
        run('xcrun', 'swiftc', '-parse-as-library', '-warnings-as-errors', '-D', 'ESTROBO_UPDATER_TESTING',
            '-target', 'arm64-apple-macosx13.0', '-F', str(sparkle), '-framework', 'Sparkle', '-framework', 'AppKit',
            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', *map(str, sources), str(HERE / 'Host.swift'), '-o', str(binary))
        run('xcrun', 'swift', str(CONSENT / 'fixture-key.swift'), str(fixture.secrets))
        private_key = fixture.secrets / 'fixture-private-key'
        public_key = (fixture.secrets / 'fixture-public-key').read_text()
        bundle_id = 'mx.loo.estrobo.adapter-fixture.' + root.name.split('-')[-1]
        for build in (1, 2, 4, 5):
            bundle = root / f'build{build}' / 'ConsentSpike.app'
            (bundle / 'Contents/MacOS').mkdir(parents=True)
            (bundle / 'Contents/Frameworks').mkdir()
            shutil.copy2(binary, bundle / 'Contents/MacOS/ConsentSpike')
            run('ditto', str(sparkle / 'Sparkle.framework'), str(bundle / 'Contents/Frameworks/Sparkle.framework'))
            info = {'CFBundleIdentifier': bundle_id, 'CFBundleName': 'ConsentSpike', 'CFBundleExecutable': 'ConsentSpike',
                    'CFBundlePackageType': 'APPL', 'CFBundleVersion': str(build), 'CFBundleShortVersionString': '0.1.0',
                    'LSMinimumSystemVersion': '13.0', 'EstroboUpdateChannel': 'beta' if build in (1, 4) else 'stable',
                    'SUPublicEDKey': public_key, 'SUFeedURL': base + '/appcast.xml', 'SUEnableAutomaticChecks': False,
                    'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False, 'SUEnableInstallerLauncherService': False,
                    'SUEnableDownloaderService': False, 'SUEnableSystemProfiling': False, 'SURequireSignedFeed': True,
                    'SUVerifyUpdateBeforeExtraction': True, 'SUSignedFeedFailureExpirationInterval': 0, 'ConsentSpikeRoot': str(root)}
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            run('codesign', '--force', '--sign', '-', str(bundle))
        dmg = root / 'update.dmg'
        run('hdiutil', 'create', '-quiet', '-volname', 'AdapterFixture', '-srcfolder', str(root / 'build2'), '-format', 'UDZO', str(dmg))
        digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
        signature = run(str(sparkle / 'bin/sign_update'), '--ed-key-file', str(private_key), '-p', str(dmg)).strip()
        feed = f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:estrobo="https://estrobo.app/xmlns/updates"><channel><title>Real Adapter Fixture</title><item><title>Stable fixture build2</title><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><description sparkle:descriptionFormat="plain-text">Fixture notes</description><estrobo:releaseNotesEn>Fixture notes</estrobo:releaseNotesEn><estrobo:releaseNotesEs>Notas de prueba</estrobo:releaseNotesEs><enclosure url="{base}/update.dmg" sparkle:version="2" sparkle:shortVersionString="0.1.0" sparkle:edSignature="{signature}" length="{dmg.stat().st_size}" type="application/octet-stream"/></item></channel></rss>'''
        def publish(text=feed):
            (root / 'appcast.xml').write_text(text)
            run(str(sparkle / 'bin/sign_update'), '--ed-key-file', str(private_key), str(root / 'appcast.xml'))
        publish()
        extra_items = []
        for build in (4, 5):
            extra_dmg = root / f'update{build}.dmg'
            run('hdiutil', 'create', '-quiet', '-volname', f'AdapterFixture{build}', '-srcfolder', str(root / f'build{build}'), '-format', 'UDZO', str(extra_dmg))
            extra_sig = run(str(sparkle / 'bin/sign_update'), '--ed-key-file', str(private_key), '-p', str(extra_dmg)).strip()
            item = feed.split('<item>')[1].split('</item>')[0]
            item = item.replace('sparkle:version="2"', f'sparkle:version="{build}"').replace('/update.dmg', f'/update{build}.dmg')
            item = item.replace(signature, extra_sig).replace(f'length="{dmg.stat().st_size}"', f'length="{extra_dmg.stat().st_size}"')
            if build == 4: item = '<sparkle:channel>beta</sparkle:channel>' + item
            if build == 5: item = item.replace('>13.0</sparkle:minimumSystemVersion>', '>99.0</sparkle:minimumSystemVersion>')
            extra_items.append('<item>' + item + '</item>')
        table_feed = feed.replace('</channel>', ''.join(extra_items) + '</channel>')
        app = root / 'installed/ConsentSpike.app'
        run('ditto', str(root / 'build1/ConsentSpike.app'), str(app))
        counter = 0
        offset = 0
        def command(action):
            nonlocal counter
            counter += 1
            temp = root / 'command.tmp'
            temp.write_text(f'{counter} {action}')
            temp.replace(root / 'command')
        def events():
            return (root / 'events.log').read_text()[offset:]
        def wait_for(value, timeout=20):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if value in events(): return
                time.sleep(.05)
            raise AssertionError(f'Timed out waiting for {value}\n{events()}')
        def begin(name):
            nonlocal offset
            offset = len((root / 'events.log').read_text())
            with (root / 'events.log').open('a') as file: file.write('CASE ' + name + '\n')
            print('CASE ' + name, flush=True)
        def passed(name, **facts):
            fixture.results.append({'case': name, 'passed': True, **facts})
            print('PASS ' + name, flush=True)
        def launch():
            (root / 'command').unlink(missing_ok=True)
            fixture.process = subprocess.Popen([str(app / 'Contents/MacOS/ConsentSpike'), str(root)], env=ENV,
                stdout=(root / 'stdout.log').open('a'), stderr=subprocess.STDOUT)
            wait_for('launched')
        def quit():
            command('key:quit')
            fixture.process.wait(timeout=15)
            time.sleep(1)
            assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '1'
        def finish_ordinary_quit(action='key:quit'):
            command(action)
            fixture.process.wait(timeout=15)
            time.sleep(1)
            assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '1'
        def archive_requests():
            return sum(r['method'] == 'GET' and r['path'] == '/update.dmg' for r in fixture.requests)
        def feed_requests():
            return sum(r['method'] == 'GET' and r['path'] == '/appcast.xml' for r in fixture.requests)
        def check_and_download():
            command('mouse:check')
            wait_for('checked builds=[2]')
            command('mouse:download')
            wait_for('downloaded sha256=')
        def clear_cache():
            shutil.rmtree(root / 'cache', ignore_errors=True)
        (root / 'artifact.json').write_text(json.dumps({'sparkle_version': shared.VERSION, 'sparkle_sha256': shared.DIGEST,
            'source_commit': run('git', '-C', str(REPO), 'rev-parse', 'HEAD').strip(), 'dmg_sha256': digest,
            'source_sha256': {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + [HERE / 'Host.swift']},
            'dmg_length': dmg.stat().st_size, 'eddsa_signature': signature, 'os': run('sw_vers').strip()}, indent=2))
        begin('missing-public-root-is-unavailable-without-network')
        info_path = app / 'Contents/Info.plist'
        configured = plistlib.loads(info_path.read_bytes())
        missing = dict(configured); missing.pop('SUPublicEDKey')
        info_path.write_bytes(plistlib.dumps(missing)); run('codesign', '--force', '--sign', '-', str(app))
        launch(); wait_for('configuration-error')
        assert not fixture.requests
        quit()
        info_path.write_bytes(plistlib.dumps(configured)); run('codesign', '--force', '--sign', '-', str(app))
        passed('missing-public-root-is-unavailable-without-network', update_requests=0)

        begin('real-service-discovery-without-preparation')
        launch()
        command('mouse:check')
        wait_for('checked builds=[2] notes-es=Notas de prueba')
        assert not any('/update.dmg' in r['path'] for r in fixture.requests)
        quit()
        passed('real-service-discovery-without-preparation', installed_build='1', archive_requests=0)

        begin('cancel-delayed-sparkle-feed-and-retry')
        launch()
        delay_feed = True
        (root / 'delayed-feed-started').unlink(missing_ok=True)
        command('mouse:check')
        deadline = time.monotonic() + 10
        while not (root / 'delayed-feed-started').exists() and time.monotonic() < deadline: time.sleep(.02)
        assert (root / 'delayed-feed-started').exists()
        command('mouse:cancel')
        wait_for('check-failed kind=cancelled', timeout=8)
        delay_feed = False
        command('mouse:check')
        wait_for('checked builds=[2]')
        assert archive_requests() == 0
        quit()
        passed('cancel-delayed-sparkle-feed-and-retry', archive_requests=0)

        begin('invalid-signed-feed-rejected')
        (root / 'appcast.xml').write_text((root / 'appcast.xml').read_text().replace('Fixture notes', 'Altered notes'))
        launch()
        command('mouse:check')
        wait_for('check-failed kind=signature')
        assert 'checked builds=' not in events()
        quit()
        publish()
        passed('invalid-signed-feed-rejected', installed_build='1')

        begin('signed-production-url-metadata-discrepancy-rejected')
        wrong = 'https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.1/estrobo-v0.1.0-beta.1-macos-universal.dmg'
        publish(feed.replace(base + '/update.dmg', wrong))
        launch(); command('mouse:check'); wait_for('check-failed kind=invalidOffer')
        assert not any('github.com' in r['host'] for r in fixture.requests)
        quit(); publish()
        passed('signed-production-url-metadata-discrepancy-rejected', installed_build='1')

        begin('own-preflight-429-preserves-retry-after')
        head_status = 429
        before = feed_requests()
        launch()
        command('mouse:check')
        wait_for('check-failed kind=rateLimit status=429')
        assert float(re.findall(r'retry=([0-9.]+)', events())[-1]) >= time.time() + 172790
        assert feed_requests() == before
        quit()
        head_status = None
        passed('own-preflight-429-preserves-retry-after', sparkle_feed_requests=0)

        begin('own-preflight-http-date-retry-after')
        head_status = 429
        retry_header = email.utils.formatdate(time.time() + 172800, usegmt=True)
        launch(); command('mouse:check'); wait_for('check-failed kind=rateLimit status=429')
        assert float(re.findall(r'retry=([0-9.]+)', events())[-1]) >= time.time() + 172790
        quit(); head_status = None; retry_header = '172800'
        passed('own-preflight-http-date-retry-after', sparkle_feed_requests=0)

        begin('signed-channel-and-compatible-build-selection')
        publish(table_feed)
        launch()
        command('mouse:check')
        wait_for('checked builds=[4]')
        quit()
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        info['EstroboUpdateChannel'] = 'stable'
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        run('codesign', '--force', '--sign', '-', str(app))
        begin('stable-channel-excludes-beta-and-incompatible')
        launch()
        command('mouse:check')
        wait_for('checked builds=[2]')
        quit()
        info['EstroboUpdateChannel'] = 'beta'
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        run('codesign', '--force', '--sign', '-', str(app))
        publish()
        passed('signed-channel-and-compatible-build-selection', beta_selected='4', stable_selected='2', excluded_incompatible='5')

        begin('two-offers-bound-durable-cache-retention')
        launch(); check_and_download()
        first = json.loads((root / 'cache/download.json').read_text())
        first_file = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(first['localFile']).path))
        publish(table_feed)
        command('mouse:check'); wait_for('checked builds=[4]')
        before_four = sum(r['path'] == '/update4.dmg' and r['method'] == 'GET' for r in fixture.requests)
        command('mouse:download')
        wait_for('downloaded sha256=' + hashlib.sha256((root / 'update4.dmg').read_bytes()).hexdigest())
        deadline = time.monotonic() + 15
        while (not (root / 'cache/download.json').exists() or json.loads((root / 'cache/download.json').read_text())['offerIdentity']['build'] != 4) and time.monotonic() < deadline: time.sleep(.05)
        assert json.loads((root / 'cache/download.json').read_text())['offerIdentity']['build'] == 4
        assert not first_file.exists()
        regular_archives = lambda: [p for p in (root / 'cache').glob('archive-*.dmg*') if p.is_file() and not p.is_symlink()]
        assert len(regular_archives()) == 1
        passed('two-offers-bound-durable-cache-retention', retained_archives=1)

        begin('cancel-new-transfer-preserves-last-valid-cache')
        publish(table_feed.replace('>99.0</sparkle:minimumSystemVersion>', '>13.0</sparkle:minimumSystemVersion>'))
        slow_archive = True
        command('mouse:check'); wait_for('checked builds=[5]')
        command('mouse:download'); wait_for('progress ')
        command('mouse:cancel'); wait_for('download-failed kind=cancelled')
        slow_archive = False
        assert json.loads((root / 'cache/download.json').read_text())['offerIdentity']['build'] == 4
        assert len(regular_archives()) == 1
        # The cache collector must not follow symlinks or remove unknown files.
        external = root / 'untouched.txt'; external.write_text('preserve fixture file')
        link = root / 'cache' / f'archive-{uuid.uuid4()}.dmg'; link.symlink_to(external)
        unknown = root / 'cache/notes.txt'; unknown.write_text('unowned')
        orphan = root / 'cache' / f'archive-{uuid.uuid4()}.dmg.partial'; orphan.write_bytes(b'orphan')
        publish(table_feed)
        command('mouse:check'); wait_for('checked builds=[4]')
        before_reuse = sum(r['path'] == '/update4.dmg' and r['method'] == 'GET' for r in fixture.requests)
        command('mouse:download'); wait_for('downloaded sha256=')
        assert sum(r['path'] == '/update4.dmg' and r['method'] == 'GET' for r in fixture.requests) == before_reuse
        assert not orphan.exists() and link.is_symlink() and external.read_text() == 'preserve fixture file' and unknown.exists()
        assert len(regular_archives()) == 1
        quit(); publish(); clear_cache()
        passed('cancel-new-transfer-preserves-last-valid-cache', retained_archives=1, reuse_archive_requests=0)

        begin('completed-download-ordinary-quit-and-process-restart')
        launch()
        check_and_download()
        assert hashlib.sha256(next((root / 'cache').glob('archive-*.dmg')).read_bytes()).hexdigest() == digest
        assert 'sparkle-extracting' not in events()
        quit()
        begin('retained-cache-last-window-close')
        launch()
        finish_ordinary_quit('mouse:window-close')
        passed('completed-download-ordinary-quit-and-process-restart', installed_build='1', cache_sha256=digest)

        begin('cached-file-tampering-rejected-before-preparation')
        launch()
        check_and_download()
        cached_file = next((root / 'cache').glob('archive-*.dmg'))
        original = cached_file.read_bytes()
        tampered = bytearray(original); tampered[len(tampered)//2] ^= 1; cached_file.write_bytes(tampered)
        command('mouse:install')
        wait_for('install-failed kind=archive')
        assert 'sparkle-extracting' not in events()
        quit()
        cached_file.write_bytes(original)
        passed('cached-file-tampering-rejected-before-preparation', installed_build='1')

        begin('fresh-signed-offer-change-rejects-old-consent')
        launch()
        check_and_download()
        publish(table_feed)
        command('mouse:install')
        wait_for('install-failed kind=invalidOffer')
        assert 'sparkle-extracting' not in events()
        quit()
        publish()
        passed('fresh-signed-offer-change-rejects-old-consent', installed_build='1')

        begin('fresh-signed-withdrawal-rejects-cached-offer')
        launch(); check_and_download()
        empty = re.sub(r'<item>.*?</item>', '', feed)
        publish(empty)
        command('mouse:install'); wait_for('install-failed kind=invalidOffer')
        assert 'sparkle-prepared' not in events()
        quit(); publish()
        passed('fresh-signed-withdrawal-rejects-cached-offer', installed_build='1')

        begin('initial-appkit-veto-prevents-preparation')
        launch(); check_and_download()
        command('mouse:veto'); wait_for('veto-armed')
        command('mouse:install'); wait_for('install-failed kind=unsafeSession')
        assert 'sparkle-prepared' not in events()
        command('mouse:unblock'); wait_for('unblocked'); quit()
        passed('initial-appkit-veto-prevents-preparation', installed_build='1')

        begin('visible-prepared-cancellation-and-final-appkit-veto')
        launch()
        check_and_download()
        command('mouse:pause')
        wait_for('lifecycle-ready')
        command('mouse:cancel')
        wait_for('install-failed kind=cancelled')
        command('mouse:pause')
        # Use event offset within this case to distinguish the second ready.
        deadline = time.monotonic() + 15
        while events().count('lifecycle-ready') < 2 and time.monotonic() < deadline: time.sleep(.05)
        assert events().count('lifecycle-ready') == 2
        command('mouse:veto'); wait_for('veto-armed')
        command('mouse:continue')
        deadline = time.monotonic() + 15
        while events().count('install-failed kind=cancelled') < 2 and time.monotonic() < deadline: time.sleep(.05)
        assert events().count('install-failed kind=cancelled') == 2
        command('mouse:unblock'); wait_for('unblocked')
        quit()
        passed('visible-prepared-cancellation-and-final-appkit-veto', installed_build='1')

        begin('ordinary-command-q-cancels-prepared-installer')
        launch(); check_and_download()
        command('mouse:pause'); wait_for('lifecycle-ready')
        finish_ordinary_quit()
        passed('ordinary-command-q-cancels-prepared-installer', installed_build='1')

        begin('ordinary-quit-in-queued-preflight-interval')
        launch(); check_and_download()
        command('mouse:install-queued'); wait_for('lifecycle-preflighting')
        finish_ordinary_quit()
        assert 'sparkle-extracting' not in events()
        passed('ordinary-quit-in-queued-preflight-interval', installed_build='1')

        begin('last-window-close-in-queued-final-commit-interval')
        launch(); check_and_download()
        command('mouse:pause'); wait_for('lifecycle-ready')
        command('mouse:queue-commit'); wait_for('final-request-queued')
        finish_ordinary_quit('mouse:window-close')
        passed('last-window-close-in-queued-final-commit-interval', installed_build='1')

        begin('cache-eviction-fails-without-archive-refetch')
        launch(); check_and_download()
        before = archive_requests()
        command('mouse:install-evict')
        wait_for('install-failed kind=archive')
        assert archive_requests() == before
        quit()
        passed('cache-eviction-fails-without-archive-refetch', additional_archive_requests=0)

        for status in (403, 429):
            begin(f'archive-http-{status}-large-body-keeps-metadata')
            clear_cache()
            archive_status = status
            launch()
            command('mouse:check'); wait_for('checked builds=[2]')
            command('mouse:download')
            wait_for(f'download-failed kind={"rateLimit" if status == 429 else "network"} status={status}')
            assert float(re.findall(r'retry=([0-9.]+)', events())[-1]) >= time.time() + 172790
            assert not (root / 'cache/download.json').exists()
            quit()
            archive_status = None
            passed(f'archive-http-{status}-large-body-keeps-metadata', http_status=status)

        begin('unexpected-archive-redirect-rejected')
        clear_cache(); archive_redirect = True
        launch(); command('mouse:check'); wait_for('checked builds=[2]')
        command('mouse:download'); wait_for('download-failed kind=network')
        quit(); archive_redirect = False
        passed('unexpected-archive-redirect-rejected', installed_build='1')

        begin('truncated-download-never-becomes-ready')
        clear_cache()
        intact = dmg.read_bytes(); dmg.write_bytes(intact[:1200])
        launch(); command('mouse:check'); wait_for('checked builds=[2]')
        command('mouse:download'); wait_for('download-failed kind=archive')
        assert not (root / 'cache/download.json').exists()
        quit(); dmg.write_bytes(intact)
        passed('truncated-download-never-becomes-ready', installed_build='1')

        begin('adulterated-download-rejected-by-real-sparkle-eddsa')
        clear_cache()
        good_archive = dmg.read_bytes()
        altered = bytearray(good_archive); altered[len(altered)//2] ^= 1; dmg.write_bytes(altered)
        launch(); check_and_download()
        command('mouse:install'); wait_for('install-failed kind=signature')
        assert 'sparkle-prepared' not in events()
        quit(); dmg.write_bytes(good_archive)
        passed('adulterated-download-rejected-by-real-sparkle-eddsa', installed_build='1')

        begin('confirmed-exact-cache-installs-and-relaunches-stable')
        clear_cache()
        launch(); check_and_download()
        before = archive_requests()
        command('mouse:install')
        wait_for('sparkle-installing')
        fixture.process.wait(timeout=20)
        wait_for('build=2 launched')
        assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '2'
        assert archive_requests() == before
        publish(table_feed)
        command('mouse:check'); wait_for('checked builds=[]')
        command('key:quit'); wait_for('build=2 appkit-close-decision 1')
        passed('confirmed-exact-cache-installs-and-relaunches-stable', installed_build='2', additional_archive_requests=0, sha256=digest)


if __name__ == '__main__':
    main()
