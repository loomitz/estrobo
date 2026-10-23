import importlib.util
import base64
import datetime
import contextlib
import hashlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'scripts/official-updater-qualification-runtime.py'
spec = importlib.util.spec_from_file_location('official_qualification_runtime', TOOL)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class QualificationRuntimeTests(unittest.TestCase):
    def test_authenticated_encrypted_transfer_rejects_modified_ciphertext(self):
        code = '''const c=require('node:crypto'); const k=c.randomBytes(32),v=c.randomBytes(12),e=c.createCipheriv('aes-256-gcm',k,v);
const b=Buffer.concat([e.update(Buffer.from('{"verified":true}')),e.final()]);
process.stdout.write(JSON.stringify({key:k.toString('hex'),cipher:Buffer.concat([v,e.getAuthTag(),b]).toString('base64')}));'''
        encrypted = json.loads(subprocess.check_output(['node', '--input-type=commonjs', '-e', code], text=True))
        cipher = base64.b64decode(encrypted['cipher'])
        self.assertEqual(runtime.decrypt_bootstrap(cipher, encrypted['key']), {'verified': True})
        damaged = bytearray(cipher); damaged[12] ^= 1
        with self.assertRaises(ValueError) as failure:
            runtime.decrypt_bootstrap(bytes(damaged), encrypted['key'])
        self.assertNotIn(encrypted['key'], str(failure.exception))

    def test_bootstrap_plaintext_is_exact_and_checked_before_writes(self):
        values = {'archive.dmg': b'original archive', 'manifest.json': b'original manifest', 'SHA256SUMS': b'original checksums'}
        expected = {name: hashlib.sha256(value).hexdigest() for name, value in values.items()}
        payload = {name: base64.b64encode(value).decode() for name, value in values.items()}
        with tempfile.TemporaryDirectory() as temporary:
            destination = pathlib.Path(temporary)
            damaged = dict(payload, **{'manifest.json': base64.b64encode(b'different manifest').decode()})
            for invalid in (damaged, dict(payload, **{'../outside': ''})):
                with self.assertRaises(ValueError):
                    runtime.unpack_bootstrap(invalid, destination, expected)
                self.assertEqual(list(destination.iterdir()), [])
            runtime.unpack_bootstrap(payload, destination, expected)
            self.assertEqual({p.name: p.read_bytes() for p in destination.iterdir()}, values)

    def test_encrypted_transfer_is_limited_to_the_temporary_project_host(self):
        names, original = self.transfer()
        receipt = dict(original, format='aes-256-gcm-json-v1', keyHex='a'*64, cipherSHA256='b'*64,
                       url='https://1234abcd.estrobo.pages.dev/qualification-transfer/'+('a'*32)+'.bin')
        receipt.pop('assets')
        with mock.patch.dict(os.environ, BOOTSTRAP_TRANSFER_JSON=json.dumps(receipt)):
            self.assertEqual(runtime.bootstrap_transfer('416881043', names), receipt)
        for url in ('https://attacker.example/blob', 'http://1234abcd.estrobo.pages.dev/qualification-transfer/a.bin',
                    'https://1234abcd.estrobo.pages.dev/qualification-transfer/'+('a'*32)+'.bin?key=secret'):
            with mock.patch.dict(os.environ, BOOTSTRAP_TRANSFER_JSON=json.dumps(dict(receipt, url=url))), self.assertRaises(ValueError):
                runtime.bootstrap_transfer('416881043', names)

    def test_lost_apple_connection_repeats_the_complete_verification(self):
        lost = subprocess.CompletedProcess(['canonical-verifier'], 1,
            stdout='api.apple-cloudkit.com: Error Domain=NSURLErrorDomain Code=-1005')
        accepted = subprocess.CompletedProcess(['canonical-verifier'], 0, stdout='verified')
        with mock.patch.object(runtime.subprocess, 'run', side_effect=[lost, accepted]) as command, \
                mock.patch.object(runtime.time, 'sleep') as delay, contextlib.redirect_stdout(io.StringIO()):
            runtime.verify_with_network_retry(pathlib.Path('/canonical-verifier'), {'EXACT_BYTES': 'unchanged'})
        self.assertEqual(command.call_count, 2)
        self.assertEqual(command.call_args_list[0], command.call_args_list[1])
        delay.assert_called_once_with(3)

    def test_invalid_ticket_is_never_retried_or_accepted(self):
        invalid = subprocess.CompletedProcess(['canonical-verifier'], 1, stdout='invalid notarization ticket')
        with mock.patch.object(runtime.subprocess, 'run', return_value=invalid) as command, \
                mock.patch.object(runtime.time, 'sleep') as delay, contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaises(subprocess.CalledProcessError):
            runtime.verify_with_network_retry(pathlib.Path('/canonical-verifier'), {})
        self.assertEqual(command.call_count, 1)
        delay.assert_not_called()

    def test_repeated_network_loss_still_fails_after_three_verifications(self):
        lost = subprocess.CompletedProcess(['canonical-verifier'], 1,
            stdout='api.apple-cloudkit.com: Error Domain=NSURLErrorDomain Code=-1005')
        with mock.patch.object(runtime.subprocess, 'run', return_value=lost) as command, \
                mock.patch.object(runtime.time, 'sleep') as delay, contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaises(subprocess.CalledProcessError):
            runtime.verify_with_network_retry(pathlib.Path('/canonical-verifier'), {})
        self.assertEqual(command.call_count, 3)
        self.assertEqual([call.args[0] for call in delay.call_args_list], [3, 6])

    def transfer(self):
        names = ['estrobo-v0.1.0-beta.5-macos-universal.dmg', 'estrobo-v0.1.0-beta.5-manifest.json', 'SHA256SUMS']
        receipt = {'releaseId': '416881043', 'expiresAt': (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=30)).isoformat(),
                   'assets': {name: {'url': 'https://release-assets.githubusercontent.com/asset?sig=temporary', 'sha256': sha}
                              for name, sha in zip(names, (runtime.BOOTSTRAP_DMG, runtime.BOOTSTRAP_MANIFEST, runtime.BOOTSTRAP_CHECKSUMS))}}
        return names, receipt

    def test_bootstrap_transfer_is_expiring_exact_and_download_only(self):
        names, receipt = self.transfer()
        with mock.patch.dict(os.environ, BOOTSTRAP_TRANSFER_JSON=json.dumps(receipt)):
            self.assertEqual(runtime.bootstrap_transfer('416881043', names), receipt['assets'])
        for field, value in [('releaseId', '416881044'), ('expiresAt', '2000-01-01T00:00:00+00:00'),
                             ('expiresAt', '2999-01-01T00:00:00+00:00')]:
            with mock.patch.dict(os.environ, BOOTSTRAP_TRANSFER_JSON=json.dumps(dict(receipt, **{field: value}))), self.assertRaises(ValueError):
                runtime.bootstrap_transfer('416881043', names)
        for url in ('http://release-assets.githubusercontent.com/a?sig=x', 'https://attacker.example/a?sig=x',
                    'https://user:password@release-assets.githubusercontent.com/a?sig=x'):
            receipt['assets'][names[0]]['url'] = url
            with mock.patch.dict(os.environ, BOOTSTRAP_TRANSFER_JSON=json.dumps(receipt)), self.assertRaises(ValueError):
                runtime.bootstrap_transfer('416881043', names)

    def test_failed_transfer_does_not_disclose_download_credential(self):
        names, receipt = self.transfer()
        asset = receipt['assets'][names[0]]
        with mock.patch.object(runtime.urllib.request, 'urlopen', side_effect=RuntimeError(asset['url'])):
            with self.assertRaises(ValueError) as failure:
                runtime.download_bootstrap(asset, pathlib.Path('/unused'), 1024)
        self.assertNotIn('sig=', str(failure.exception))
        self.assertNotIn('temporary', str(failure.exception).replace('temporary transfer', 'transfer'))

    def test_exact_distinct_immutable_tuple_is_required(self):
        valid = {'source_sha': 'a'*40, 'dmg_sha256': 'b'*64, 'manifest_sha256': 'c'*64,
                 'feed_sha256': 'd'*64, 'bootstrap_release_id': '416881043', 'candidate_release_id': '416881044'}
        self.assertEqual(runtime.validate_inputs(valid), valid)
        for field, replacement in [('source_sha', 'main'), ('dmg_sha256', 'latest'),
                                   ('manifest_sha256', 'a'*63), ('feed_sha256', 'A'*64),
                                   ('candidate_release_id', '../releases/latest'),
                                   ('candidate_release_id', valid['bootstrap_release_id'])]:
            with self.subTest(field=field, replacement=replacement), self.assertRaises(ValueError):
                runtime.validate_inputs(dict(valid, **{field: replacement}))

    def test_entry_point_refuses_a_maintainer_host_before_any_preparation(self):
        work = pathlib.Path.home() / 'estrobo-qualification'
        existed = work.exists()
        result = subprocess.run([sys.executable, '-B', str(TOOL), 'prepare'],
                                env=dict(os.environ, GITHUB_ACTIONS='false'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('disposable GitHub-hosted macOS user', result.stderr)
        self.assertEqual(work.exists(), existed)


if __name__ == '__main__':
    unittest.main()
