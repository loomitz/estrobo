#!/usr/bin/env python3
"""Pinned macOS updater dependency and artifact boundary. Never publishes a release."""
import argparse
import base64
import json
import os
import plistlib
import re
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

VERSION = '2.10.0'
SHA256 = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
# Exact top-level LICENSE from the archive pinned above, including external notices.
NOTICE_SHA256 = '389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe'
ROOT = pathlib.Path(__file__).resolve().parent.parent


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def dependency(directory, archive=None):
    archive = pathlib.Path(archive) if archive else ROOT / '.build/Sparkle' / f'Sparkle-{VERSION}.tar.xz'
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as download:
            downloaded = pathlib.Path(download.name)
        try:
            urllib.request.urlretrieve(f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz', downloaded)
            if digest(downloaded) != SHA256:
                raise ValueError('Sparkle archive integrity mismatch')
            downloaded.replace(archive)
        finally:
            downloaded.unlink(missing_ok=True)
    if digest(archive) != SHA256:
        raise ValueError('Sparkle archive integrity mismatch')
    directory = pathlib.Path(directory)
    with tarfile.open(archive, 'r:xz') as source:
        members = [item for item in source.getmembers() if item.name.removeprefix('./').startswith('Sparkle.framework/') or item.name.removeprefix('./') in ('bin/sign_update', 'bin/generate_keys', 'LICENSE')]
        if not directory.exists():
            directory.parent.mkdir(parents=True, exist_ok=True)
            staging = pathlib.Path(tempfile.mkdtemp(prefix='sparkle-verified-', dir=directory.parent))
            try:
                source.extractall(staging, members=members, filter='data')
                staging.rename(directory)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        expected = set()
        for member in members:
            relative = member.name.removeprefix('./')
            expected.add(relative.rstrip('/'))
            expected.update(parent.as_posix() for parent in pathlib.PurePosixPath(relative).parents if parent.as_posix() != '.')
            path = directory / relative
            if member.issym():
                valid = path.is_symlink() and path.readlink().as_posix() == member.linkname
            elif member.isdir():
                valid = path.is_dir() and not path.is_symlink()
            elif member.isfile():
                valid = path.is_file() and not path.is_symlink() and digest(path) == hashlib.sha256(source.extractfile(member).read()).hexdigest() and (path.stat().st_mode & 0o111) == (member.mode & 0o111)
            else:
                valid = False
            if not valid:
                raise ValueError(f'Sparkle dependency integrity mismatch: {relative}')
        actual = {path.relative_to(directory).as_posix() for path in (directory / 'Sparkle.framework').rglob('*')}
        if actual - expected:
            raise ValueError(f'Unexpected Sparkle framework content: {sorted(actual - expected)}')
    return directory


def validate_release_metadata(version, build, channel, tag):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Marketing version must have three canonical numeric components')
    if not re.fullmatch(r'[1-9][0-9]*', str(build)):
        raise ValueError('Build must be a positive canonical integer')
    expected = f'v{version}-beta.{build}' if channel == 'beta' else f'v{version}+build.{build}'
    if channel not in ('stable', 'beta') or tag not in ({expected, f'v{version}'} if channel == 'stable' else {expected}):
        raise ValueError(f'Release tag does not match explicit channel/version/build: expected {expected}')


def public_key(value, required=False):
    if not value and not required:
        return None
    try:
        decoded = base64.b64decode(value or '', validate=True)
    except ValueError:
        decoded = b''
    if len(decoded) != 32 or base64.b64encode(decoded).decode() != value:
        raise ValueError('A canonical 32-byte SPARKLE_PUBLIC_ED_KEY is required for distribution')
    return value


def distribution_allocation(version, build, channel, tag):
    ledger = json.loads((ROOT / 'release/macos-builds.json').read_text())
    allocations = ledger['allocations']
    numbers = [item['build'] for item in allocations]
    if ledger['schemaVersion'] != 1 or numbers != sorted(set(numbers)):
        raise ValueError('Global build allocation ledger is invalid')
    matches = [item for item in allocations if item['build'] == int(build)]
    if len(matches) != 1 or any(matches[0][name] != value for name,value in [('version',version),('channel',channel),('tag',tag)]):
        raise ValueError('Distribution version/channel/tag must match an assigned global build')
    if int(build) < 5:
        raise ValueError('Updater distribution cannot reuse the pre-updater beta builds')


def configure(app, version, build, channel, tag, key, distribution=False):
    validate_release_metadata(version, build, channel, tag)
    key = public_key(key, required=distribution)
    if distribution:
        distribution_allocation(version, build, channel, tag)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleShortVersionString=version, CFBundleVersion=str(build), EstroboUpdateChannel=channel, EstroboReleaseTag=tag,
                EstroboSparkleVersion=VERSION, SUFeedURL='https://estrobo.app/updates/macos/appcast.xml',
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
                SUEnableInstallerLauncherService=True, SUEnableDownloaderService=False,
                SUEnableSystemProfiling=False, SUEnableJavaScript=False, SUShowReleaseNotes=False,
                SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True, SUSignedFeedFailureExpirationInterval=0)
    info.pop('SUPublicEDKey', None)
    if key:
        info['SUPublicEDKey'] = key
    if info.get('NSAppTransportSecurity'):
        raise ValueError('Updater bundles must use default ATS without exceptions')
    plist.write_bytes(plistlib.dumps(info))


def embed(app, directory, archive):
    dependency(directory, archive)
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/usr/bin/ditto', str(directory / 'Sparkle.framework'), str(framework)], check=True)
    for name in ('Headers', 'PrivateHeaders', 'Modules'):
        (framework / name).unlink()
        shutil.rmtree(framework / 'Versions/B' / name)
    shutil.rmtree(framework / 'Versions/B/XPCServices/Downloader.xpc')
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(directory / 'LICENSE', resources / 'Sparkle-LICENSE.txt')


def verify_bundle(app, distribution=False):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    validate_release_metadata(info['CFBundleShortVersionString'], info['CFBundleVersion'], info.get('EstroboUpdateChannel'), info.get('EstroboReleaseTag'))
    public_key(info.get('SUPublicEDKey'), required=distribution)
    if distribution:
        distribution_allocation(info['CFBundleShortVersionString'], info['CFBundleVersion'], info['EstroboUpdateChannel'], info['EstroboReleaseTag'])
    if distribution and info.get('SUPublicEDKey') != public_key(os.environ.get('SPARKLE_PUBLIC_ED_KEY'), required=True):
        raise ValueError('Bundle public key differs from the approved SPARKLE_PUBLIC_ED_KEY input')
    required = {'CFBundleIdentifier': 'mx.loo.estrobo', 'EstroboSparkleVersion': VERSION,
                'SUFeedURL': 'https://estrobo.app/updates/macos/appcast.xml',
                'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False,
                'SUEnableInstallerLauncherService': True, 'SUEnableDownloaderService': False,
                'SUEnableSystemProfiling': False, 'SUEnableJavaScript': False, 'SUShowReleaseNotes': False,
                'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True, 'SUSignedFeedFailureExpirationInterval': 0}
    for name, expected in required.items():
        if info.get(name) != expected or type(info.get(name)) is not type(expected):
            raise ValueError(f'Incorrect updater bundle setting: {name}')
    if info.get('NSAppTransportSecurity'):
        raise ValueError('Updater bundles must use default ATS without exceptions')
    notice = app / 'Contents/Resources/Sparkle-LICENSE.txt'
    if not notice.is_file() or notice.is_symlink() or digest(notice) != NOTICE_SHA256:
        raise ValueError('Required exact Sparkle/third-party notices are missing or altered')
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    framework_info = plistlib.loads((framework / 'Versions/B/Resources/Info.plist').read_bytes())
    if framework_info.get('CFBundleShortVersionString') != VERSION or framework_info.get('CFBundleIdentifier') != 'org.sparkle-project.Sparkle':
        raise ValueError('Embedded framework does not match the pinned Sparkle version/identity')
    layout = json.loads((ROOT / 'release/sparkle-2.10.0-layout.json').read_text())
    actual = {path.relative_to(framework).as_posix(): path for path in framework.rglob('*')}
    if set(actual) != set(layout):
        raise ValueError(f'Unexpected/missing Sparkle framework content: extra={sorted(set(actual)-set(layout))}; missing={sorted(set(layout)-set(actual))}')
    for relative, contract in layout.items():
        path = actual[relative]
        if contract['kind'] == 'symlink':
            valid = path.is_symlink() and path.readlink().as_posix() == contract['target']
        elif contract['kind'] == 'directory':
            valid = path.is_dir() and not path.is_symlink()
        else:
            valid = path.is_file() and not path.is_symlink() and bool(path.stat().st_mode & 0o111) == contract['executable']
        if not valid:
            raise ValueError(f'Unexpected Sparkle framework type/permissions: {relative}')
    main = app / 'Contents/MacOS/estrobo'
    if not main.is_file() or not os.access(main, os.X_OK):
        raise ValueError('Main executable missing')
    forbidden_suffixes = {'.swift', '.m', '.mm', '.c', '.h', '.py', '.js', '.sh', '.p12', '.pfx', '.p8', '.key', '.pem', '.cer', '.mobileprovision', '.zip', '.dmg', '.pkg', '.o', '.a', '.dylib', '.so'}
    for path in (app / 'Contents').rglob('*'):
        if path.is_relative_to(framework):
            continue
        if path.is_symlink():
            raise ValueError(f'Unexpected bundle symlink: {path}')
        if path.suffix.lower() in forbidden_suffixes or path.name in ('Makefile', '.DS_Store', '.env') or path.name.startswith('.env.'):
            raise ValueError(f'Forbidden bundle content: {path}')
        if path.is_dir() and (path.suffix in ('.app', '.xpc', '.framework') or path.name in ('Tests', 'Sources', 'Build', 'Dist', '.git', 'node_modules')):
            raise ValueError(f'Unexpected bundle directory: {path}')
        if path.is_file() and path != main:
            with path.open('rb') as stream:
                magic = stream.read(4).hex()
            if magic in {'feedface','feedfacf','cefaedfe','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca'}:
                raise ValueError(f'Unexpected binary outside the approved component paths: {path}')
        if path.is_file() and path.stat().st_mode & 0o111 and path != main:
            raise ValueError(f'Unexpected executable in bundle: {path}')
    return info


HOST_ENTITLEMENTS = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.device.bluetooth': True,
    'com.apple.security.network.client': True,
    'com.apple.security.temporary-exception.mach-lookup.global-name': ['mx.loo.estrobo-spks', 'mx.loo.estrobo-spki'],
}


def components(app):
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    return [framework / 'Versions/B/Autoupdate', framework / 'Versions/B/Updater.app',
            framework / 'Versions/B/XPCServices/Installer.xpc', framework, app]


def sign(app, identity, entitlements, keychain=None):
    verify_bundle(app, distribution=identity != '-')
    if plistlib.loads(entitlements.read_bytes()) != HOST_ENTITLEMENTS:
        raise ValueError('Host entitlements must match the exact updater allowlist')
    with tempfile.TemporaryDirectory(prefix='estrobo-updater-sign-') as temporary:
        empty = pathlib.Path(temporary) / 'empty.plist'
        empty.write_bytes(plistlib.dumps({}))
        for component in components(app):
            # Ad hoc development signatures have no Team ID. Hardened Runtime
            # library validation cannot authenticate their embedded framework.
            # Explicit zero also clears flags inherited from vendor signatures.
            command = ['/usr/bin/codesign', '--force', '--sign', identity, '--options', '0' if identity == '-' else 'runtime',
                       '--timestamp=none' if identity == '-' else '--timestamp', '--entitlements', str(entitlements if component == app else empty)]
            if keychain:
                command.extend(['--keychain', keychain])
            subprocess.run([*command, str(component)], check=True)


def verify_signatures(app, distribution=False, team=None, certificate=None):
    verify_bundle(app, distribution)
    environment = dict(os.environ)
    for component in components(app):
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(component)], check=True)
        details = subprocess.run(['/usr/bin/codesign', '-dvvv', str(component)], capture_output=True, text=True, check=True).stderr
        if distribution and not re.search(r'flags=.*\(.*runtime.*\)', details):
            raise ValueError(f'Hardened Runtime missing: {component}')
        entitlement_result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', '--xml', str(component)], capture_output=True, check=True)
        effective = plistlib.loads(entitlement_result.stdout) if entitlement_result.stdout.strip() else {}
        if effective != (HOST_ENTITLEMENTS if component == app else {}):
            raise ValueError(f'Unexpected effective entitlements: {component}')
        if distribution:
            if not team or not certificate:
                raise ValueError('Developer ID verification requires pinned certificate and Team ID')
            if 'Authority=Developer ID Application:' not in details or f'TeamIdentifier={team}\n' not in details or not re.search(r'^Timestamp=', details, re.M):
                raise ValueError(f'Invalid Developer ID authority/timestamp/team: {component}')
            with tempfile.TemporaryDirectory(prefix='estrobo-updater-cert-') as temporary:
                prefix = pathlib.Path(temporary) / 'certificate'
                subprocess.run(['/usr/bin/codesign', '-d', '--extract-certificates=' + str(prefix), str(component)], check=True, capture_output=True)
                if pathlib.Path(str(prefix) + '0').read_bytes() != certificate.read_bytes():
                    raise ValueError(f'Nested signature certificate differs from pinned identity: {component}')
        if component == app:
            binary = app / 'Contents/MacOS/estrobo'
        elif component.suffix in ('.app', '.xpc'):
            info = plistlib.loads((component / 'Contents/Info.plist').read_bytes())
            binary = component / 'Contents/MacOS' / info['CFBundleExecutable']
        elif component.suffix == '.framework':
            binary = component / 'Versions/B/Sparkle'
        else:
            binary = component
        for arch in ('arm64', 'x86_64'):
            subprocess.run(['/usr/bin/lipo', str(binary), '-verify_arch', arch], check=True)
        libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(binary)], text=True, env=environment)
        for line in libraries.splitlines():
            if not line.startswith('\t'):
                continue
            library = line.strip().split(' (', 1)[0]
            if library.startswith(('/System/Library/', '/usr/lib/')):
                continue
            allowed = {'@rpath/Sparkle.framework/Versions/B/Sparkle', '@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle'}
            if library not in allowed:
                raise ValueError(f'Non-self-contained dynamic dependency {library}: {component}')
    print(f'Updater component signatures and universal slices verified: {app}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pinned = commands.add_parser('dependency')
    pinned.add_argument('--directory', required=True, type=pathlib.Path)
    pinned.add_argument('--archive', type=pathlib.Path)
    for name in ('configure', 'embed', 'verify-bundle', 'sign', 'verify-signatures', 'metadata'):
        command = commands.add_parser(name)
        if name != 'metadata':
            command.add_argument('--app', required=True, type=pathlib.Path)
        if name in ('configure', 'verify-bundle', 'verify-signatures', 'metadata'):
            command.add_argument('--distribution', action='store_true')
        if name == 'sign':
            command.add_argument('--identity', required=True)
            command.add_argument('--entitlements', required=True, type=pathlib.Path)
            command.add_argument('--keychain')
        if name == 'verify-signatures':
            command.add_argument('--team')
            command.add_argument('--certificate', type=pathlib.Path)
        if name == 'embed':
            command.add_argument('--directory', required=True, type=pathlib.Path)
            command.add_argument('--archive', type=pathlib.Path)
        if name in ('configure', 'metadata'):
            for field in ('version', 'build', 'channel', 'tag'):
                command.add_argument('--' + field, required=True)
            command.add_argument('--public-key', default=os.environ.get('SPARKLE_PUBLIC_ED_KEY'))
    args = parser.parse_args()
    if args.command == 'dependency':
        print(dependency(args.directory, args.archive))
    elif args.command == 'metadata':
        validate_release_metadata(args.version, args.build, args.channel, args.tag)
        public_key(args.public_key, required=args.distribution)
        if args.distribution:
            distribution_allocation(args.version, args.build, args.channel, args.tag)
    elif args.command == 'configure':
        configure(args.app, args.version, args.build, args.channel, args.tag, args.public_key, args.distribution)
    elif args.command == 'embed':
        embed(args.app, args.directory, args.archive)
    elif args.command == 'sign':
        sign(args.app, args.identity, args.entitlements, args.keychain)
    elif args.command == 'verify-signatures':
        verify_signatures(args.app, args.distribution, args.team, args.certificate)
    elif args.command == 'verify-bundle':
        verify_bundle(args.app, args.distribution)
        print(f'Updater bundle contents verified: {args.app}')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'macOS updater artifact verification failed: {error}', file=sys.stderr)
        sys.exit(1)
