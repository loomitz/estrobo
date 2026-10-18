#!/usr/bin/env python3
"""Approved catalog/site boundary: exact signed bytes and permanent withdrawals."""
import hashlib
import base64
import os
import plistlib
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'scripts/macos-update-catalog.py'

class CatalogTests(unittest.TestCase):
    def test_unconfigured_site_removes_a_stale_feed_and_serves_revalidation_headers(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-catalog-test-') as temporary:
            temporary = pathlib.Path(temporary)
            public = temporary / 'public'
            stale = public / 'updates/macos/appcast.xml'
            stale.parent.mkdir(parents=True)
            stale.write_text('unapproved feed')
            published = temporary / 'published.json'
            published.write_text(json.dumps({'revision':0, 'withdrawnBuilds':[]}))
            result = subprocess.run(['python3', str(TOOL), 'site', '--source', str(ROOT / 'release/macos-updates'), '--public', str(public), '--published-state', str(published)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(stale.exists())
            headers = (public / '_headers').read_text()
            self.assertIn('/updates/macos/appcast.xml', headers)
            self.assertIn('no-cache, max-age=0, must-revalidate', headers)
            self.assertNotIn('stale-if-error', headers)

    def test_approved_site_preserves_signed_bytes_and_refuses_withdrawn_or_mutated_feed(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-catalog-test-') as temporary:
            temporary = pathlib.Path(temporary)
            source = temporary / 'source'
            source.mkdir()
            public = temporary / 'public'
            keydir = temporary / 'keys'
            keydir.mkdir()
            environment = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))
            subprocess.run(['xcrun', 'swift', str(ROOT / 'prototype/MacUpdaterConsentSpike/fixture-key.swift'), str(keydir)], check=True, env=environment)
            tools = pathlib.Path(os.environ.get('SPARKLE_DIR', str(ROOT / '.build/Sparkle/2.10.0')))
            offer = {'build': '5', 'version': '0.1.0', 'channel': 'beta', 'tag': 'v0.1.0-beta.5', 'minimumMacOSVersion': '13.0', 'architectures': ['arm64', 'x86_64'], 'releaseNotes': {'en':'Fixture only', 'es':'Sólo fixture'}, 'archive': {'url': 'https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.5/estrobo-v0.1.0-beta.5-macos-universal.dmg', 'length': 123, 'sha256': 'a'*64, 'edSignature': base64.b64encode(b'x'*64).decode()}}
            feed = source / 'appcast.xml'
            feed.write_text('<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:estrobo="https://estrobo.app/xmlns/updates"><channel><title>Estrobo</title><item><title>0.1.0</title><description>Fixture only</description><estrobo:releaseNotesEn>Fixture only</estrobo:releaseNotesEn><estrobo:releaseNotesEs>Sólo fixture</estrobo:releaseNotesEs><sparkle:version>5</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><enclosure url="'+offer['archive']['url']+'" length="123" sparkle:edSignature="'+offer['archive']['edSignature']+'" type="application/octet-stream"/></item></channel></rss>')
            subprocess.run([str(tools / 'bin/sign_update'), '--ed-key-file', str(keydir / 'fixture-private-key'), str(feed)], check=True, capture_output=True)
            subprocess.run([str(tools / 'bin/sign_update'), '--ed-key-file', str(keydir / 'fixture-private-key'), '--verify', str(feed)], check=True, capture_output=True)
            (source / 'catalog.json').write_text(json.dumps({'schemaVersion': 1, 'offers': [offer]}))
            (source / 'withdrawals.json').write_text(json.dumps({'schemaVersion': 1, 'withdrawals': []}))
            approval = {'schemaVersion': 1, 'state': 'approved', 'revision': 1, 'publicKey': (keydir / 'fixture-public-key').read_text(), 'verifiedWith': 'Sparkle 2.10.0 sign_update', 'feedSHA256': hashlib.sha256(feed.read_bytes()).hexdigest(), 'catalogSHA256': hashlib.sha256((source / 'catalog.json').read_bytes()).hexdigest(), 'withdrawalsSHA256': hashlib.sha256((source / 'withdrawals.json').read_bytes()).hexdigest()}
            (source / 'approval.json').write_text(json.dumps(approval))
            published = temporary / 'published.json'
            published.write_text(json.dumps({'revision': 0, 'withdrawnBuilds': []}))
            command = ['python3', str(TOOL), 'site', '--source', str(source), '--public', str(public), '--published-state', str(published)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((public / 'updates/macos/appcast.xml').read_bytes(), feed.read_bytes())
            (source / 'withdrawals.json').write_text(json.dumps({'schemaVersion': 1, 'withdrawals': [{'build': '5', 'reason': 'Fixture retirement'}]}))
            approval['withdrawalsSHA256'] = hashlib.sha256((source / 'withdrawals.json').read_bytes()).hexdigest()
            (source / 'approval.json').write_text(json.dumps(approval))
            rejected = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('withdrawn', rejected.stderr.lower())
            (source / 'withdrawals.json').write_text(json.dumps({'schemaVersion': 1, 'withdrawals': []}))
            approval['withdrawalsSHA256'] = hashlib.sha256((source / 'withdrawals.json').read_bytes()).hexdigest()
            (source / 'approval.json').write_text(json.dumps(approval))
            feed.write_bytes(feed.read_bytes() + b'<!-- changed after approval -->')
            rejected = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('digest', rejected.stderr.lower())

    def test_unconfigured_editorial_build_cannot_erase_a_published_withdrawal_history(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-catalog-test-') as temporary:
            temporary = pathlib.Path(temporary)
            public = temporary / 'public'
            state = public / 'updates/macos/state.json'
            state.parent.mkdir(parents=True)
            state.write_text(json.dumps({'revision':3, 'withdrawnBuilds':['5'], 'feedSHA256':'a'*64}))
            result = subprocess.run(['python3', str(TOOL), 'site', '--source', str(ROOT / 'release/macos-updates'), '--public', str(public), '--published-state', str(state)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('published', result.stderr.lower())
            self.assertTrue(state.exists())

if __name__ == '__main__':
    unittest.main()
