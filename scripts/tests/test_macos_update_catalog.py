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
import xml.etree.ElementTree as XML

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'scripts/macos-update-catalog.py'

class CatalogTests(unittest.TestCase):
    def test_prepare_and_approve_reject_consumer_limits_before_signing_or_public_requests(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-catalog-early-bounds-test-') as temporary:
            temporary = pathlib.Path(temporary)
            source = temporary / 'source'
            source.mkdir()
            (source / 'approval.json').write_text(json.dumps({'state': 'unconfigured'}))
            (source / 'catalog.json').write_text(json.dumps({'schemaVersion': 1, 'offers': []}))
            for length, es in [(67_108_865, 'Fixture'), (123, 'á' * 8_192 + 'a')]:
                with self.subTest(length=length, esBytes=len(es.encode())):
                    candidate = temporary / 'candidate'
                    candidate.mkdir(exist_ok=True)
                    approval = write_catalog_fixture(candidate, length=length, en='Fixture', es=es)
                    candidate_data = dict(approval, state='candidate', baseRevision=0, baseFeedSHA256=None)
                    (candidate / 'candidate.json').write_text(json.dumps(candidate_data))
                    approved = subprocess.run(['python3', str(TOOL), 'approve', '--source', str(source), '--candidate', str(candidate), '--expected-feed-sha256', approval['feedSHA256'], '--account', 'NONEXISTENT_FIXTURE_ACCOUNT'], capture_output=True, text=True)
                    self.assertNotEqual(approved.returncode, 0)
                    self.assertIn('consumer limit', approved.stderr.lower())
                    archive = temporary / 'fixture.dmg'
                    with archive.open('wb') as stream:
                        stream.truncate(length)
                    manifest = temporary / 'manifest.json'
                    # Signing/source approval metadata intentionally absent: an
                    # unusable payload must be rejected before those boundaries.
                    manifest.write_text(json.dumps({'product': {'version': '0.1.0', 'build': '5', 'updateChannel': 'beta'}, 'source': {'tag': 'v0.1.0-beta.5'}}))
                    en_file, es_file = temporary / 'en.txt', temporary / 'es.txt'
                    en_file.write_text('Fixture')
                    es_file.write_text(es)
                    prepared = subprocess.run(['python3', str(TOOL), 'prepare', '--source', str(source), '--archive', str(archive), '--manifest', str(manifest), '--checksums', str(temporary / 'unused-checksums'), '--notes-en', str(en_file), '--notes-es', str(es_file), '--account', 'NONEXISTENT_FIXTURE_ACCOUNT', '--output', str(temporary / 'unused-output')], capture_output=True, text=True, env=dict(os.environ, SPARKLE_PUBLIC_ED_KEY=base64.b64encode(bytes(32)).decode()))
                    self.assertNotEqual(prepared.returncode, 0)
                    self.assertIn('consumer limit', prepared.stderr.lower())
                    self.assertFalse((temporary / 'unused-output').exists())

    def test_site_accepts_consumer_boundaries_and_rejects_oversized_archives_and_utf8_notes(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-catalog-bounds-test-') as temporary:
            temporary = pathlib.Path(temporary)
            source = temporary / 'source'
            source.mkdir()
            published = temporary / 'published.json'
            published.write_text(json.dumps({'revision': 0, 'withdrawnBuilds': []}))
            for length, en, es, valid in [
                (67_108_864, 'a' * 16_384, 'á' * 8_192, True),
                (67_108_865, 'Fixture', 'Fixture', False),
                (123, 'a' * 16_385, 'Fixture', False),
                (123, 'Fixture', 'á' * 8_192 + 'a', False),
            ]:
                with self.subTest(length=length, enBytes=len(en.encode()), esBytes=len(es.encode())):
                    write_catalog_fixture(source, length=length, en=en, es=es)
                    result = subprocess.run(['python3', str(TOOL), 'site', '--source', str(source), '--public', str(temporary / 'public'), '--published-state', str(published)], capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, valid, result.stderr)
                    if not valid:
                        self.assertIn('consumer limit', result.stderr.lower())

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

def write_catalog_fixture(source, *, length, en, es):
    """Reviewed-byte fixture only; no signing key, Keychain or public offer."""
    signature = base64.b64encode(b'x' * 64).decode()
    url = 'https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.5/estrobo-v0.1.0-beta.5-macos-universal.dmg'
    offer = {'build': '5', 'version': '0.1.0', 'channel': 'beta', 'tag': 'v0.1.0-beta.5', 'minimumMacOSVersion': '13.0', 'architectures': ['arm64', 'x86_64'], 'releaseNotes': {'en': en, 'es': es}, 'archive': {'url': url, 'length': length, 'sha256': 'a' * 64, 'edSignature': signature}}
    rss = XML.Element('rss', {'xmlns:sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle', 'xmlns:estrobo': 'https://estrobo.app/xmlns/updates'})
    item = XML.SubElement(XML.SubElement(rss, 'channel'), 'item')
    for name, value in [('title', '0.1.0'), ('description', en), ('estrobo:releaseNotesEn', en), ('estrobo:releaseNotesEs', es), ('sparkle:version', '5'), ('sparkle:shortVersionString', '0.1.0'), ('sparkle:channel', 'beta'), ('sparkle:minimumSystemVersion', '13.0')]:
        XML.SubElement(item, name).text = value
    XML.SubElement(item, 'enclosure', {'url': url, 'length': str(length), 'sparkle:edSignature': signature, 'type': 'application/octet-stream'})
    (source / 'appcast.xml').write_bytes(XML.tostring(rss, encoding='utf-8'))
    (source / 'catalog.json').write_text(json.dumps({'schemaVersion': 1, 'offers': [offer]}))
    (source / 'withdrawals.json').write_text(json.dumps({'schemaVersion': 1, 'withdrawals': []}))
    approval = {'schemaVersion': 1, 'state': 'approved', 'revision': 1, 'publicKey': base64.b64encode(bytes(32)).decode(), 'verifiedWith': 'Sparkle 2.10.0 sign_update'}
    for filename, field in [('appcast.xml', 'feedSHA256'), ('catalog.json', 'catalogSHA256'), ('withdrawals.json', 'withdrawalsSHA256')]:
        approval[field] = hashlib.sha256((source / filename).read_bytes()).hexdigest()
    (source / 'approval.json').write_text(json.dumps(approval))
    return approval

if __name__ == '__main__':
    unittest.main()
