#!/usr/bin/env python3
"""Disposable hosted macOS qualification. Read-only release/feed authority."""
import argparse
import base64
import datetime
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
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOME = pathlib.Path.home()
WORK = HOME / 'estrobo-qualification'
FEED = 'https://estrobo.app/updates/macos/appcast.xml'
BOOTSTRAP_COMMIT = 'e10629c0d84fce46a25488f726cb5e6dba98d627'
BOOTSTRAP_DMG = '2a663503219c6b139167de407121342b8d15dfb546079796195c04b2e3b38345'
BOOTSTRAP_MANIFEST = '38da8a041a2364c2d76a24f4858bccbc00534c2db5611fa87c4831a132408504'
BOOTSTRAP_CHECKSUMS = 'b2855cbdf559f6107515683a1ab52b7c26defae23bb15f12223534eb5b2a998e'


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


def bootstrap_transfer(release_id, names):
    # A contents:read Actions token cannot read a draft. The maintainer supplies
    # short-lived asset download URLs, never a token with release write access.
    transfer = json.loads(os.environ.get('BOOTSTRAP_TRANSFER_JSON', '{}'))
    now = datetime.datetime.now(datetime.timezone.utc)
    expiry = datetime.datetime.fromisoformat(transfer.get('expiresAt', '1970-01-01T00:00:00+00:00'))
    if str(transfer.get('releaseId')) != release_id or expiry.tzinfo is None or not now < expiry <= now + datetime.timedelta(hours=2):
        raise ValueError('An exact unexpired read-only bootstrap transfer is required')
    if transfer.get('format') == 'aes-256-gcm-json-v1':
        url = urllib.parse.urlsplit(transfer.get('url', ''))
        if (url.scheme != 'https' or not re.fullmatch(r'[a-z0-9]{8}\.estrobo\.pages\.dev', url.hostname or '') or
                url.username or url.password or url.port or url.query or url.fragment or
                not re.fullmatch(r'/qualification-transfer/[a-f0-9]{32}\.bin', url.path) or
                not re.fullmatch('[a-f0-9]{64}', transfer.get('keyHex', '')) or
                not re.fullmatch('[a-f0-9]{64}', transfer.get('cipherSHA256', ''))):
            raise ValueError('Encrypted bootstrap transfer must identify the reviewed temporary host and exact ciphertext')
        return transfer
    assets = transfer.get('assets', {})
    expected = dict(zip(names, (BOOTSTRAP_DMG, BOOTSTRAP_MANIFEST, BOOTSTRAP_CHECKSUMS)))
    if set(assets) != set(expected):
        raise ValueError('Bootstrap transfer must contain exactly the pinned tuple')
    for name, asset in assets.items():
        url = urllib.parse.urlsplit(asset.get('url', ''))
        if (url.scheme != 'https' or url.hostname != 'release-assets.githubusercontent.com' or
                url.username or url.password or url.port or url.fragment or not url.query or
                asset.get('sha256') != expected[name]):
            raise ValueError('Bootstrap transfer differs from the pinned GitHub asset identity')
    return assets


def decrypt_bootstrap(ciphertext, key):
    # Use Node's audited crypto implementation. Keys are passed on stdin,
    # never in command arguments, a URL, or diagnostic output.
    code = '''const crypto = require('node:crypto');
let input=''; process.stdin.on('data', x => input += x); process.stdin.on('end', () => {
  try { const x=JSON.parse(input), b=Buffer.from(x.cipher, 'base64');
    const d=crypto.createDecipheriv('aes-256-gcm', Buffer.from(x.key, 'hex'), b.subarray(0,12));
    d.setAuthTag(b.subarray(12,28));
    process.stdout.write(Buffer.concat([d.update(b.subarray(28)), d.final()]));
  } catch { process.exitCode=1; }
});'''
    result = subprocess.run(['node', '--input-type=commonjs', '-e', code],
        input=json.dumps({'cipher': base64.b64encode(ciphertext).decode(), 'key': key}),
        capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError('Encrypted bootstrap authentication failed')
    return json.loads(result.stdout)


def unpack_bootstrap(payload, destination, expected):
    if not isinstance(payload, dict) or set(payload) != set(expected):
        raise ValueError('Decrypted bootstrap must contain exactly the pinned tuple')
    decoded = {name: base64.b64decode(payload[name], validate=True) for name in expected}
    if any(hashlib.sha256(data).hexdigest() != expected[name] for name, data in decoded.items()):
        raise ValueError('Decrypted bootstrap differs from the pinned immutable tuple')
    for name, data in decoded.items():
        if pathlib.Path(name).name != name or name in ('.', '..'):
            raise ValueError('Unsafe bootstrap filename')
    for name, data in decoded.items():
        with (destination/name).open('xb') as output:
            output.write(data)


def download_encrypted_bootstrap(transfer, destination, names):
    try:
        request = urllib.request.Request(transfer['url'], headers={'User-Agent': 'EstroboQualificationVerifier/1.0'})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.url != transfer['url']:
                raise ValueError('Unexpected redirect')
            ciphertext = response.read(32*1024*1024+1)
        if not 28 < len(ciphertext) <= 32*1024*1024 or hashlib.sha256(ciphertext).hexdigest() != transfer['cipherSHA256']:
            raise ValueError('Ciphertext digest/size mismatch')
    except Exception:
        raise ValueError('Encrypted read-only bootstrap download failed') from None
    expected = dict(zip(names, (BOOTSTRAP_DMG, BOOTSTRAP_MANIFEST, BOOTSTRAP_CHECKSUMS)))
    unpack_bootstrap(decrypt_bootstrap(ciphertext, transfer['keyHex']), destination, expected)


def download_bootstrap(asset, destination, limit):
    try:
        request = urllib.request.Request(asset['url'], headers={'User-Agent': 'EstroboQualificationVerifier/1.0'})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.url != asset['url']:
                raise ValueError('Unexpected redirect')
            data = response.read(limit+1)
        if len(data) > limit or hashlib.sha256(data).hexdigest() != asset['sha256']:
            raise ValueError('Bootstrap download digest/size mismatch')
    except Exception:
        # Do not expose temporary signed URLs in Actions logs or tracebacks.
        raise ValueError('Read-only bootstrap download failed; refresh its temporary transfer') from None
    destination.write_bytes(data)


def verify_with_network_retry(script, environment):
    for attempt in range(3):
        result = subprocess.run([str(script)], env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end='', flush=True)
        if result.returncode == 0:
            return
        transient = ('NSURLErrorDomain Code=-1005' in result.stdout and
                     'api.apple-cloudkit.com' in result.stdout)
        if not transient or attempt == 2:
            result.check_returncode()
        print('Apple ticket lookup lost its connection; repeating the complete read-only verification.', flush=True)
        time.sleep(3*(attempt+1))


def release_tuple(release_id, build, expected_source, expected_dmg, expected_manifest):
    destination = WORK / ('build'+build)
    destination.mkdir()
    tag = 'v0.1.0-beta.'+build
    names = ['estrobo-'+tag+'-macos-universal.dmg', 'estrobo-'+tag+'-manifest.json', 'SHA256SUMS']
    if build == '5':
        assets = bootstrap_transfer(release_id, names)
        if assets.get('format') == 'aes-256-gcm-json-v1':
            download_encrypted_bootstrap(assets, destination, names)
        else:
            for name in names:
                download_bootstrap(assets[name], destination/name, 64*1024*1024 if name.endswith('.dmg') else 1024*1024)
    else:
        release = json.loads(run(['gh', 'api', 'repos/loomitz/estrobo/releases/'+release_id]))
        if release['tag_name'] != tag or not release['prerelease'] or release['draft']:
            raise ValueError('Qualification requires the exact public beta release')
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
    verify_with_network_retry(ROOT/'scripts/verify-macos-developer-id-dmg.sh', environment)
    return archive


def native_network_probe(mode):
    result = run(['swift', str(ROOT/'prototype/OfficialUpdaterQualification/NetworkProbe.swift'), mode])
    return json.loads(result)


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
    subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                    '-f', '/Applications/estrobo.app'], check=True)
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
    native_trace = native_network_probe('trace')
    for probe in native_trace:
        address = probe.get('address')
        if address and ipaddress.ip_address(address).is_global:
            addresses.add(str(ipaddress.ip_address(address)))
    metadata = {'architecture': platform.machine(), 'macOS': run(['sw_vers', '-productVersion']),
                'addresses': sorted(addresses), 'sourceCommit': inputs['source_sha'],
                'archiveSHA256': inputs['dmg_sha256'], 'expectedFeedSHA256': inputs['feed_sha256'],
                'bootstrap': 'Exact immutable bootstrap transport; browser quarantine is not claimed',
                'nativeNetworkTrace': native_trace,
                'bootstrapTransport': 'encrypted temporary preview' if json.loads(os.environ.get('BOOTSTRAP_TRANSFER_JSON', '{}')).get('format') == 'aes-256-gcm-json-v1' else 'read-only GitHub assets'}
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
                    probes = native_network_probe('feed')
                    (WORK/'evidence/native-network-preflight.json').write_text(json.dumps(probes, indent=2)+'\n')
                    if any(p.get('status') != 200 for p in probes) or probes[-1].get('sha256') != plan['feed_sha256']:
                        raise ValueError('Native URLSession official-feed probe failed; inspect scoped preflight evidence')
                    print('The exact official HTTPS feed is available to this test VM.')
                    return
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(15)
    raise ValueError('The exact bounded official feed was not made available within 30 minutes')


def verify_installed():
    plan = json.loads((WORK/'plan.json').read_text())
    if not (WORK/'evidence/result.json').is_file():
        raise ValueError('Native UI result is absent; a skipped test cannot qualify the update')
    result = json.loads((WORK/'evidence/result.json').read_text())
    if result.get('passed') is not True or result.get('archiveSHA256') != plan['dmg_sha256']:
        raise ValueError('Native runtime did not complete the authorized update')
    environment = dict(os.environ, APP_BUNDLE='/Applications/estrobo.app', VERSION='0.1.0', BUILD_NUMBER='6',
        UPDATE_CHANNEL='beta', TAG='v0.1.0-beta.6', SOURCE_COMMIT=plan['source_sha'], BUNDLE_IDENTIFIER='mx.loo.estrobo',
        MACOSX_DEPLOYMENT_TARGET='13.0', DEVELOPER_ID_TEAM_ID='XG96FAV89U',
        DEVELOPER_ID_CERTIFICATE=str(ROOT/'release/signing/estrobo-developer-id-application.cer'),
        DEVELOPER_ID_CERTIFICATE_SHA256=str(ROOT/'release/signing/estrobo-developer-id-application.sha256'))
    verify_with_network_retry(ROOT/'scripts/verify-macos-developer-id-release.sh', environment)
    result.update(architecture=platform.machine(), macOS=run(['sw_vers', '-productVersion']),
                  sourceCommit=plan['source_sha'], installedSignatureAndNotarizationVerified=True)
    (WORK/'evidence/result.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'wait-feed', 'verify-installed'))
    args = parser.parse_args()
    hosted_only()
    {'prepare': prepare, 'wait-feed': wait_feed, 'verify-installed': verify_installed}[args.command]()
