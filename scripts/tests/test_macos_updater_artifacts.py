#!/usr/bin/env python3
"""Public artifact CLI contracts, using the official pinned Sparkle distribution."""
import json
import base64
import os
import pathlib
import plistlib
import runpy
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'scripts/macos-updater-artifacts.py'
ARCHIVE = pathlib.Path(os.environ.get('SPARKLE_ARCHIVE') or str(ROOT / '.build/Sparkle/Sparkle-2.10.0.tar.xz'))

class ArtifactTests(unittest.TestCase):
    def test_pinned_dependency_rejects_modified_override(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-updater-artifact-test-') as temporary:
            dependency = pathlib.Path(temporary) / 'dependency'
            command = ['python3', str(TOOL), 'dependency', '--directory', str(dependency), '--archive', str(ARCHIVE)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            binary = dependency / 'Sparkle.framework/Versions/B/Sparkle'
            self.assertTrue(binary.is_file())
            with binary.open('ab') as stream:
                stream.write(b'tampered')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('integrity', result.stderr.lower())

    def test_embedded_bundle_rejects_unexpected_executable_and_missing_release_trust(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-updater-artifact-test-') as temporary:
            temporary = pathlib.Path(temporary)
            dependency = temporary / 'dependency'
            def invoke(*args):
                return subprocess.run(['python3', str(TOOL), *map(str, args)], capture_output=True, text=True)
            self.assertEqual(invoke('dependency', '--directory', dependency, '--archive', ARCHIVE).returncode, 0)
            app = temporary / 'estrobo.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy('/usr/bin/true', app / 'Contents/MacOS/estrobo')
            shutil.copy2(ROOT / 'prototype/EstroboMac/Info.plist', app / 'Contents/Info.plist')
            configure = ['configure', '--app', app, '--version', '0.1.0', '--build', '5', '--channel', 'beta', '--tag', 'v0.1.0-beta.5']
            rejected = invoke(*configure, '--distribution')
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('public', rejected.stderr.lower())
            self.assertEqual(invoke(*configure).returncode, 0)
            result = invoke('embed', '--app', app, '--directory', dependency, '--archive', ARCHIVE)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((app / 'Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc').exists())
            verified = invoke('verify-bundle', '--app', app)
            self.assertEqual(verified.returncode, 0, verified.stderr)
            extra = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/surprise'
            shutil.copy('/usr/bin/true', extra)
            rejected = invoke('verify-bundle', '--app', app)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('unexpected', rejected.stderr.lower())

    def test_inside_out_signatures_preserve_exact_entitlements_and_universal_helpers(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-updater-sign-test-') as temporary:
            temporary = pathlib.Path(temporary)
            app = temporary / 'estrobo.app'
            dependency = temporary / 'dependency'
            def invoke(*args):
                return subprocess.run(['python3', str(TOOL), *map(str, args)], capture_output=True, text=True)
            self.assertEqual(invoke('dependency', '--directory', dependency, '--archive', ARCHIVE).returncode, 0)
            (app / 'Contents/MacOS').mkdir(parents=True)
            source = temporary / 'main.c'
            source.write_text('int main(void) { return 0; }')
            environment = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))
            subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=13.0', str(source), '-o', str(app / 'Contents/MacOS/estrobo')], check=True, env=environment)
            shutil.copy2(ROOT / 'prototype/EstroboMac/Info.plist', app / 'Contents/Info.plist')
            self.assertEqual(invoke('configure', '--app', app, '--version', '0.1.0', '--build', '5', '--channel', 'stable', '--tag', 'v0.1.0+build.5').returncode, 0)
            self.assertEqual(invoke('embed', '--app', app, '--directory', dependency, '--archive', ARCHIVE).returncode, 0)
            result = invoke('sign', '--app', app, '--identity', '-', '--entitlements', ROOT / 'prototype/EstroboMac/EstroboMac.entitlements')
            self.assertEqual(result.returncode, 0, result.stderr)
            framework = app / 'Contents/Frameworks/Sparkle.framework'
            signed_components = [framework / 'Versions/B/Autoupdate', framework / 'Versions/B/Updater.app',
                                 framework / 'Versions/B/XPCServices/Installer.xpc', framework, app]
            for component in signed_components:
                details = subprocess.run(['/usr/bin/codesign', '-dvvv', str(component)], capture_output=True, text=True, check=True).stderr
                self.assertIn('Signature=adhoc', details)
                self.assertNotIn('runtime', details, 'An ad hoc development component has no Team ID for library validation')
            result = invoke('verify-signatures', '--app', app)
            self.assertEqual(result.returncode, 0, result.stderr)
            # A fixture-only public key permits the release metadata check. It is
            # never accepted as proof of Developer ID, timestamp or notarization.
            fixture_key = base64.b64encode(bytes(range(32))).decode()
            self.assertEqual(invoke('configure', '--app', app, '--version', '0.1.0', '--build', '5', '--channel', 'beta',
                                    '--tag', 'v0.1.0-beta.5', '--public-key', fixture_key, '--distribution').returncode, 0)
            environment = dict(os.environ, SPARKLE_PUBLIC_ED_KEY=fixture_key)
            rejected = subprocess.run(['python3', str(TOOL), 'verify-signatures', '--app', str(app), '--distribution'],
                                      capture_output=True, text=True, env=environment)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('Hardened Runtime missing', rejected.stderr)
            # Exercise the public command parser and real bundle validation, and
            # record only the external signer boundary without using a credential.
            calls = []
            def record_signer(command, **kwargs):
                self.assertEqual(command[0], '/usr/bin/codesign')
                calls.append((command, plistlib.loads(pathlib.Path(command[command.index('--entitlements') + 1]).read_bytes())))
                return subprocess.CompletedProcess(command, 0)
            arguments = [str(TOOL), 'sign', '--app', str(app), '--identity', 'Developer ID Application: fixture (TESTTEAM)',
                         '--entitlements', str(ROOT / 'prototype/EstroboMac/EstroboMac.entitlements')]
            with mock.patch.dict(os.environ, environment), mock.patch('sys.argv', arguments), mock.patch('subprocess.run', side_effect=record_signer):
                runpy.run_path(str(TOOL), run_name='__main__')
            self.assertEqual([pathlib.Path(command[-1]) for command, _ in calls], signed_components)
            for command, entitlements in calls:
                self.assertEqual(command[command.index('--options') + 1], 'runtime')
                self.assertIn('--timestamp', command)
                self.assertEqual(entitlements, plistlib.loads((ROOT / 'prototype/EstroboMac/EstroboMac.entitlements').read_bytes()) if pathlib.Path(command[-1]) == app else {})
            installed = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate'
            with installed.open('ab') as stream:
                stream.write(b'altered')
            self.assertNotEqual(invoke('verify-signatures', '--app', app).returncode, 0)

    def test_stable_rebuild_tags_keep_marketing_version_and_global_build_independent(self):
        for tag, valid in [('v0.1.0+build.6', True), ('v0.1.0', True), ('v0.1.0+build.5', False), ('v0.1.0-beta.6', False)]:
            result = subprocess.run(['python3', str(TOOL), 'metadata', '--version', '0.1.0', '--build', '6', '--channel', 'stable', '--tag', tag], capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_legacy_verifier_never_accepts_an_unconfigured_framework_exception(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-legacy-bundle-test-') as temporary:
            app = pathlib.Path(temporary) / 'estrobo.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy('/usr/bin/true', app / 'Contents/MacOS/estrobo')
            extra = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Unexpected'
            extra.parent.mkdir(parents=True)
            shutil.copy('/usr/bin/true', extra)
            result = subprocess.run([str(ROOT / 'scripts/verify-macos-bundle-contents.sh'), str(app)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, 'A framework exception requires verified updater metadata')

    def test_updater_bundle_rejects_macho_disguised_as_nonexecutable_resource(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-updater-smuggle-test-') as temporary:
            temporary = pathlib.Path(temporary)
            dependency = temporary / 'dependency'
            app = temporary / 'estrobo.app'
            def invoke(*args):
                return subprocess.run(['python3', str(TOOL), *map(str,args)], capture_output=True, text=True)
            self.assertEqual(invoke('dependency', '--directory', dependency, '--archive', ARCHIVE).returncode,0)
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy('/usr/bin/true',app / 'Contents/MacOS/estrobo')
            shutil.copy2(ROOT / 'prototype/EstroboMac/Info.plist',app / 'Contents/Info.plist')
            self.assertEqual(invoke('configure','--app',app,'--version','0.1.0','--build','5','--channel','beta','--tag','v0.1.0-beta.5').returncode,0)
            self.assertEqual(invoke('embed','--app',app,'--directory',dependency,'--archive',ARCHIVE).returncode,0)
            resource=app / 'Contents/Resources/hidden.png'
            resource.parent.mkdir()
            shutil.copy('/usr/bin/true',resource)
            resource.chmod(0o644)
            rejected=invoke('verify-bundle','--app',app)
            self.assertNotEqual(rejected.returncode,0)
            self.assertIn('binary',rejected.stderr.lower())

if __name__ == '__main__':
    unittest.main()
