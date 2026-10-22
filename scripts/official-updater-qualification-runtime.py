#!/usr/bin/env python3
"""Disposable hosted macOS qualification. Read-only release/feed authority."""
import argparse
import hashlib
import ipaddress
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOME = pathlib.Path.home()
WORK = HOME / 'estrobo-qualification'
FEED = 'https://estrobo.app/updates/macos/appcast.xml'
BOOTSTRAP_COMMIT = 'e10629c0d84fce46a25488f726cb5e6dba98d627'
BOOTSTRAP_DMG = '2a663503219c6b139167de407121342b8d15dfb546079796195c04b2e3b38345'
BOOTSTRAP_MANIFEST = '38da8a041a2364c2d76a24f4858bccbc00534c2db5611fa87c4831a132408504'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments, **kwargs):
    return subprocess.check_output(list(map(str, arguments)), text=True, **kwargs).strip()


def hosted_only():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or platform.system() != 'Darwin' or HOME != pathlib.Path('/Users/runner'):
        raise ValueError('This command may run only in a disposable GitHub-hosted macOS user')


def validate_inputs(inputs):
    for key in ('source_sha', 'dmg_sha256', 'manifest_sha256', 'feed_sha256'):
        length = 40 if key == 'source_sha' else 64
        if not re.fullmatch('[0-9a-f]{'+str(length)+'}', inputs.get(key, '')):
            raise ValueError('Exact source/artifact/feed digests are required')
    for key in ('bootstrap_release_id', 'candidate_release_id'):
        if not re.fullmatch('[1-9][0-9]{0,18}', inputs.get(key, '')):
            raise ValueError('An immutable release ID is required')
    if inputs['bootstrap_release_id'] == inputs['candidate_release_id']:
        raise ValueError('Two distinct releases are required')
    return inputs


def release_tuple(release_id, build, expected_source, expected_dmg, expected_manifest):
    destination = WORK / ('build'+build)
    destination.mkdir()
    release = json.loads(run(['gh', 'api', 'repos/loomitz/estrobo/releases/'+release_id]))
    tag = 'v0.1.0-beta.'+build
    if release['tag_name'] != tag or not release['prerelease']:
        raise ValueError('Qualification requires the exact beta release')
    names = ['estrobo-'+tag+'-macos-universal.dmg', 'estrobo-'+tag+'-manifest.json', 'SHA256SUMS']
    assets = {asset['name']: asset for asset in release['assets']}
    if set(assets) != set(names):
        raise ValueError('The release must contain exactly DMG, manifest and checksums')
    for name in names:
        with (destination / name).open('xb') as output:
            subprocess.run(['gh', 'api', '-H', 'Accept: application/octet-stream',
                            'repos/loomitz/estrobo/releases/assets/'+str(assets[name]['id'])], stdout=output, check=True)
    archive, manifest = destination / names[0], destination / names[1]
    if digest(archive) != expected_dmg or digest(manifest) != expected_manifest:
        raise ValueError('Downloaded release differs from the authorized exact tuple')
    data = json.loads(manifest.read_text())
    if data['source']['commit'] != expected_source or str(data['product']['build']) != build:
        raise ValueError('Release source/build mismatch')
    if build == '6' and (data['verification']['physicalSmoke'] != 'pending' or 'localReleaseApproval' in data['verification']):
        raise ValueError('The qualification manifest must keep final physical approval honestly pending')
    environment = dict(os.environ, DMG=str(archive), MANIFEST=str(manifest), CHECKSUMS=str(destination/'SHA256SUMS'),
        VERSION='0.1.0', BUILD_NUMBER=build, TAG=tag, COMMIT=expected_source, UPDATE_CHANNEL='beta',
        MACOSX_DEPLOYMENT_TARGET='13.0', BUNDLE_IDENTIFIER='mx.loo.estrobo', DEVELOPER_ID_TEAM_ID='XG96FAV89U',
        DEVELOPER_ID_CERTIFICATE=str(ROOT/'release/signing/estrobo-developer-id-application.cer'),
        DEVELOPER_ID_CERTIFICATE_SHA256=str(ROOT/'release/signing/estrobo-developer-id-application.sha256'),
        APP_VERIFY_SCRIPT=str(ROOT/'scripts/verify-macos-developer-id-release.sh'))
    subprocess.run([str(ROOT/'scripts/verify-macos-developer-id-dmg.sh')], env=environment, check=True)
    return archive


def prepare():
    inputs = validate_inputs(json.loads(os.environ['QUALIFICATION_INPUT_JSON']))
    subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', inputs['source_sha'], 'origin/main'], check=True)
    if WORK.exists() or pathlib.Path('/Applications/estrobo.app').exists():
        raise ValueError('Qualification requires a fresh user with no existing app or evidence')
    WORK.mkdir(mode=0o700)
    (WORK/'evidence').mkdir(mode=0o700)
    # Dependency download is pinned and content verified by the canonical tool.
    subprocess.run(['python3', str(ROOT/'scripts/macos-updater-artifacts.py'), 'dependency',
                    '--directory', str(ROOT/'.build/Sparkle/2.10.0')], check=True)
    bootstrap = release_tuple(inputs['bootstrap_release_id'], '5', BOOTSTRAP_COMMIT, BOOTSTRAP_DMG, BOOTSTRAP_MANIFEST)
    release_tuple(inputs['candidate_release_id'], '6', inputs['source_sha'], inputs['dmg_sha256'], inputs['manifest_sha256'])
    with tempfile.TemporaryDirectory(prefix='estrobo-bootstrap-') as temporary:
        mount = pathlib.Path(temporary)/'mount'; mount.mkdir()
        subprocess.run(['hdiutil', 'attach', '-quiet', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(bootstrap)], check=True)
        try:
            subprocess.run(['ditto', str(mount/'estrobo.app'), '/Applications/estrobo.app'], check=True)
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    if pathlib.Path('/Applications/estrobo.app').stat().st_uid != os.getuid():
        raise ValueError('The app must be owned by the isolated test user')
    shutil.copyfile(ROOT/'prototype/OfficialUpdaterQualification/Fixtures/synthetic-preferences.plist', WORK/'synthetic-preferences.plist')
    plan = dict(inputs, dmgSHA256=inputs['dmg_sha256'], purpose='official-updater-qualification')
    (WORK/'plan.json').write_text(json.dumps(plan, indent=2)+'\n')
    addresses = set()
    for family in ('-4', '-6'):
        response = subprocess.run(['curl', family, '--fail', '--silent', '--show-error', '--max-time', '15',
                                   'https://estrobo.app/cdn-cgi/trace'], capture_output=True, text=True)
        if response.returncode == 0:
            fields = dict(line.split('=', 1) for line in response.stdout.splitlines() if '=' in line)
            if 'ip' in fields and ipaddress.ip_address(fields['ip']).is_global:
                addresses.add(fields['ip'])
    if not addresses:
        raise ValueError('Could not establish exact public test egress addresses')
    metadata = {'architecture': platform.machine(), 'macOS': run(['sw_vers', '-productVersion']),
                'addresses': sorted(addresses), 'sourceCommit': inputs['source_sha'],
                'archiveSHA256': inputs['dmg_sha256'], 'expectedFeedSHA256': inputs['feed_sha256'],
                'bootstrap': 'Authenticated GitHub draft download; browser quarantine is not claimed'}
    (WORK/'runner-metadata.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print('Exact release tuples verified and bootstrap installed in the fresh user. No signing credentials were supplied.')


def wait_feed():
    plan = json.loads((WORK/'plan.json').read_text())
    deadline = time.monotonic()+30*60
    while time.monotonic() < deadline:
        request = urllib.request.Request(FEED, headers={'Cache-Control': 'no-cache', 'User-Agent': 'EstroboQualificationVerifier/1.0'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(1_048_577)
                if response.url == FEED and len(data) <= 1_048_576 and hashlib.sha256(data).hexdigest() == plan['feed_sha256']:
                    if response.headers.get('Cache-Control') != 'private, no-store':
                        raise ValueError('Qualification feed lacks its private cache policy')
                    (WORK/'evidence/official-appcast.xml').write_bytes(data)
                    print('The exact official HTTPS feed is available to this test VM.')
                    return
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(15)
    raise ValueError('The exact bounded official feed was not made available within 30 minutes')


def verify_installed():
    plan = json.loads((WORK/'plan.json').read_text())
    result = json.loads((WORK/'evidence/result.json').read_text())
    if result.get('passed') is not True or result.get('archiveSHA256') != plan['dmg_sha256']:
        raise ValueError('Native runtime did not complete the authorized update')
    environment = dict(os.environ, APP_BUNDLE='/Applications/estrobo.app', VERSION='0.1.0', BUILD_NUMBER='6',
        UPDATE_CHANNEL='beta', TAG='v0.1.0-beta.6', SOURCE_COMMIT=plan['source_sha'], BUNDLE_IDENTIFIER='mx.loo.estrobo',
        MACOSX_DEPLOYMENT_TARGET='13.0', DEVELOPER_ID_TEAM_ID='XG96FAV89U',
        DEVELOPER_ID_CERTIFICATE=str(ROOT/'release/signing/estrobo-developer-id-application.cer'),
        DEVELOPER_ID_CERTIFICATE_SHA256=str(ROOT/'release/signing/estrobo-developer-id-application.sha256'))
    subprocess.run([str(ROOT/'scripts/verify-macos-developer-id-release.sh')], env=environment, check=True)
    result.update(architecture=platform.machine(), macOS=run(['sw_vers', '-productVersion']),
                  sourceCommit=plan['source_sha'], installedSignatureAndNotarizationVerified=True)
    (WORK/'evidence/result.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'wait-feed', 'verify-installed'))
    args = parser.parse_args()
    hosted_only()
    {'prepare': prepare, 'wait-feed': wait_feed, 'verify-installed': verify_installed}[args.command]()
