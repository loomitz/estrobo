#!/usr/bin/env python3
"""Local signed appcast candidates and approved static-site bytes. No deployment API."""
import argparse
import base64
import datetime
import importlib.util
import os
import re
import subprocess
import tempfile
import urllib.request
import urllib.error
import urllib.parse
import xml.etree.ElementTree as XML
import hashlib
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
module_spec = importlib.util.spec_from_file_location('updater_artifacts', ROOT / 'scripts/macos-updater-artifacts.py')
artifacts = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(artifacts)
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
ESTROBO = '{https://estrobo.app/xmlns/updates}'
STATE_URL = 'https://estrobo.app/updates/macos/state.json'
HEADERS = '/updates/macos/appcast.xml\n  Cache-Control: no-cache, max-age=0, must-revalidate\n  Content-Type: application/xml; charset=utf-8\n  X-Content-Type-Options: nosniff\n'
# Shipped macOS consumer contract (UpdateHTTPClient / SparkleUpdateService).
MAXIMUM_ARCHIVE_BYTES = 64 * 1024 * 1024
MAXIMUM_NOTES_UTF8_BYTES = 16_384


def read_json(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_consumer_limits(length, notes):
    if type(length) is not int or not 0 < length <= MAXIMUM_ARCHIVE_BYTES:
        raise ValueError('Archive exceeds consumer limit: 1–67,108,864 bytes')
    if set(notes) != {'en', 'es'} or any(not isinstance(note, str) or not note.strip() for note in notes.values()):
        raise ValueError('Self-contained release notes in English and Spanish are required')
    if any(len(note.encode('utf-8')) > MAXIMUM_NOTES_UTF8_BYTES for note in notes.values()):
        raise ValueError('Release notes exceed consumer limit: 16,384 UTF-8 bytes per language')


def validate_catalog(catalog, withdrawals):
    if catalog.get('schemaVersion') != 1 or withdrawals.get('schemaVersion') != 1:
        raise ValueError('Unsupported catalog schema')
    retired = {str(item['build']) for item in withdrawals['withdrawals']}
    if len(retired) != len(withdrawals['withdrawals']) or any(not re.fullmatch(r'[1-9][0-9]*', str(item['build'])) or not item.get('reason') for item in withdrawals['withdrawals']):
        raise ValueError('Withdrawal records must preserve unique positive builds and their reasons')
    builds = set()
    for offer in catalog['offers']:
        artifacts.validate_release_metadata(offer['version'], offer['build'], offer['channel'], offer['tag'])
        build = str(offer['build'])
        if build in retired:
            raise ValueError(f'Withdrawn build cannot reappear: {build}')
        if build in builds:
            raise ValueError(f'Duplicate build in catalog: {build}')
        builds.add(build)
        archive = offer['archive']
        validate_consumer_limits(archive['length'], offer['releaseNotes'])
        expected = f"https://github.com/loomitz/estrobo/releases/download/{offer['tag']}/estrobo-{offer['tag']}-macos-universal.dmg"
        if archive['url'] != expected:
            raise ValueError('Archive URL must identify the exact GitHub release DMG; aliases are forbidden')
        if not re.fullmatch('[0-9a-f]{64}', archive['sha256']):
            raise ValueError('Invalid final archive length/SHA-256')
        try:
            signature = base64.b64decode(archive['edSignature'], validate=True)
        except ValueError:
            signature = b''
        if len(signature) != 64:
            raise ValueError('Invalid archive EdDSA signature')
        if offer['architectures'] != ['arm64', 'x86_64']:
            raise ValueError('Distributed archives must contain both supported architectures')
        if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', offer['minimumMacOSVersion']):
            raise ValueError('Invalid minimum system version')
    return retired


def policy_text(policy):
    return json.dumps(policy, sort_keys=True, separators=(',', ':'))


def validate_qualification(policy, catalog, active=False):
    if not isinstance(policy, dict) or set(policy) != {'purpose', 'authorizedAt', 'expiresAt', 'authorizationSHA256', 'build', 'tag', 'commit', 'dmgSHA256'}:
        raise ValueError('Malformed qualification policy')
    if policy['purpose'] != 'official-updater-qualification':
        raise ValueError('Invalid qualification purpose')
    for field, size in [('authorizationSHA256', 64), ('commit', 40), ('dmgSHA256', 64)]:
        if not isinstance(policy[field], str) or not re.fullmatch('[0-9a-f]{'+str(size)+'}', policy[field]):
            raise ValueError('Invalid qualification identity')
    start = datetime.datetime.fromisoformat(policy['authorizedAt'])
    end = datetime.datetime.fromisoformat(policy['expiresAt'])
    if start.utcoffset() != datetime.timedelta(0) or end.utcoffset() != datetime.timedelta(0) or not datetime.timedelta(0) < end-start <= datetime.timedelta(hours=48):
        raise ValueError('Qualification must have UTC dates and last at most 48 hours')
    now = datetime.datetime.now(datetime.timezone.utc)
    if active and (start > now or end <= now):
        raise ValueError('Qualification is not active or has expired')
    if len(catalog['offers']) != 1:
        raise ValueError('Qualification requires exactly one beta offer')
    offer = catalog['offers'][0]
    if offer['channel'] != 'beta' or any(str(offer[field]) != policy[field] for field in ('build', 'tag')) or offer['archive']['sha256'] != policy['dmgSHA256']:
        raise ValueError('Qualification differs from exact beta archive')


def validate_feed(feed, catalog, qualification=None):
    data = feed.read_bytes()
    if b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('External XML declarations are forbidden')
    # Empty signed feeds are necessary to withdraw the last offer. Their
    # signature is the feed footer, not an absent enclosure attribute.
    if b'sparkle:edSignature=' not in data and b'<!-- sparkle-signatures:\nedSignature: ' not in data:
        raise ValueError('Signed feed marker missing')
    rss = XML.fromstring(data)
    if rss.tag != 'rss' or rss.find('channel') is None:
        raise ValueError('Invalid appcast XML')
    markers = rss.findall('./channel/' + ESTROBO + 'qualification')
    if qualification is not None:
        validate_qualification(qualification, catalog)
        if len(markers) != 1 or markers[0].text != policy_text(qualification) or markers[0].attrib or len(markers[0]):
            raise ValueError('Signed qualification policy differs from catalog approval')
    elif markers:
        raise ValueError('Signed qualification cannot become an unrestricted catalog')
    items = rss.findall('./channel/item')
    if len(items) != len(catalog['offers']):
        raise ValueError('Feed does not match approved catalog item count')
    offers = {str(offer['build']): offer for offer in catalog['offers']}
    seen = set()
    allowed_children = {'title', 'description', SPARKLE+'version', SPARKLE+'shortVersionString', SPARKLE+'channel', SPARKLE+'minimumSystemVersion', 'enclosure', ESTROBO+'releaseNotesEn', ESTROBO+'releaseNotesEs'}
    for item in items:
        if any(child.tag not in allowed_children or len(child) for child in item):
            raise ValueError('Remote notes, external resources, delta/package or unsupported feed fields are forbidden')
        tags = [child.tag for child in item]
        if len(tags) != len(set(tags)) or item.attrib:
            raise ValueError('Ambiguous duplicate appcast fields are forbidden')
        build = item.findtext(SPARKLE+'version')
        offer = offers.get(build)
        if offer is None or build in seen:
            raise ValueError('Feed includes an unapproved/duplicate build')
        seen.add(build)
        enclosure = item.find('enclosure')
        expected_enclosure = {'url':offer['archive']['url'], 'length':str(offer['archive']['length']), SPARKLE+'edSignature':offer['archive']['edSignature'], 'type':'application/octet-stream'}
        if enclosure is None or enclosure.attrib != expected_enclosure:
            raise ValueError('Feed archive identity differs from approved exact DMG')
        if item.findtext(SPARKLE+'shortVersionString') != offer['version'] or item.findtext(SPARKLE+'minimumSystemVersion') != offer['minimumMacOSVersion'] or item.findtext('description') != offer['releaseNotes']['en'] or item.findtext(ESTROBO+'releaseNotesEn') != offer['releaseNotes']['en'] or item.findtext(ESTROBO+'releaseNotesEs') != offer['releaseNotes']['es']:
            raise ValueError('Feed metadata differs from approved catalog')
        if item.findtext(SPARKLE+'channel') != ('beta' if offer['channel']=='beta' else None):
            raise ValueError('Installed channel must not be inferred from version or tag')


def validate_approved(source):
    approval = read_json(source / 'approval.json')
    if approval.get('schemaVersion') != 1 or approval.get('state') != 'approved' or type(approval.get('revision')) is not int or approval['revision'] < 1:
        raise ValueError('Unsupported catalog approval')
    artifacts.public_key(approval['publicKey'], required=True)
    if approval.get('verifiedWith') != 'Sparkle 2.10.0 sign_update':
        raise ValueError('Official signed-feed verification is required before approval')
    for filename, field in [('appcast.xml','feedSHA256'), ('catalog.json','catalogSHA256'), ('withdrawals.json','withdrawalsSHA256')]:
        if sha(source / filename) != approval[field]:
            raise ValueError(f'Approved catalog digest mismatch: {filename}')
    catalog = read_json(source / 'catalog.json')
    withdrawals = read_json(source / 'withdrawals.json')
    retired = validate_catalog(catalog, withdrawals)
    validate_feed(source / 'appcast.xml', catalog, approval.get('qualification'))
    return approval, retired


class HTTPSOnlyRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, url):
        if urllib.parse.urlparse(url).scheme != 'https':
            raise ValueError('Insecure HTTP redirect is forbidden')
        return super().redirect_request(request, file, code, message, headers, url)


def open_https(request, timeout):
    if urllib.parse.urlparse(request.full_url).scheme != 'https':
        raise ValueError('Only HTTPS distribution requests are permitted')
    return urllib.request.build_opener(HTTPSOnlyRedirects()).open(request, timeout=timeout)


def validate_published_state(state):
    if type(state.get('revision')) is not int or state['revision'] < 0 or not isinstance(state.get('withdrawnBuilds'), list):
        raise ValueError('Malformed published catalog state')
    if any(not isinstance(build,str) or not re.fullmatch(r'[1-9][0-9]*',build) for build in state['withdrawnBuilds']):
        raise ValueError('Malformed published withdrawal history')
    if state['revision'] > 0 and not re.fullmatch('[0-9a-f]{64}', state.get('feedSHA256','')):
        raise ValueError('Published revision lacks its exact feed digest')
    return state


def published_state(path, revision):
    if path:
        return validate_published_state(read_json(path))
    request = urllib.request.Request(STATE_URL, headers={'Cache-Control':'no-cache', 'Accept':'application/json', 'User-Agent':'EstroboCatalogVerifier/1.0'})
    try:
        with open_https(request, timeout=30) as response:
            if not response.url.startswith('https://estrobo.app/'):
                raise ValueError('Published state redirected outside the trusted HTTPS site')
            return validate_published_state(json.load(response))
    except urllib.error.HTTPError as error:
        if error.code == 404 and revision == 1:
            return {'revision':0, 'withdrawnBuilds':[]}
        raise


def site(source, public, published=None):
    approval = read_json(source / 'approval.json')
    target = public / 'updates/macos/appcast.xml'
    state_target = target.with_name('state.json')
    if approval.get('state') == 'unconfigured':
        live = published_state(published, 1)
        if live['revision'] != 0 or live['withdrawnBuilds']:
            raise ValueError('Unconfigured bootstrap cannot erase published catalog or withdrawal history')
        if read_json(source / 'catalog.json')['offers']:
            raise ValueError('An unconfigured catalog cannot contain offers')
        target.unlink(missing_ok=True)
        state_target.unlink(missing_ok=True)
    else:
        approval, retired = validate_approved(source)
        live = published_state(published, approval['revision'])
        if approval['revision'] < live['revision'] or not set(live['withdrawnBuilds']).issubset(retired):
            raise ValueError('Published withdrawal/revision state would be rolled back by this editorial build')
        if approval['revision'] == live['revision'] and live.get('feedSHA256') != approval['feedSHA256']:
            raise ValueError('Published revision is immutable; promote a new revision')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / 'appcast.xml', target)
        state_target.write_text(json.dumps({'revision':approval['revision'], 'withdrawnBuilds':sorted(retired), 'feedSHA256':approval['feedSHA256']}, indent=2)+'\n')
    public.mkdir(parents=True, exist_ok=True)
    (public / '_headers').write_text(HEADERS + '\n/updates/macos/state.json\n  Cache-Control: no-cache, max-age=0, must-revalidate\n  Content-Type: application/json; charset=utf-8\n')
    worker, routes = public / '_worker.js', public / '_routes.json'
    qualification = approval.get('qualification')
    if qualification:
        template = (ROOT / 'scripts/macos-update-qualification-worker.mjs').read_text()
        worker.write_text(template.replace('__ESTROBO_QUALIFICATION_EXPIRES_AT__', qualification['expiresAt']).replace('__ESTROBO_QUALIFICATION_FEED_BASE64__', base64.b64encode(target.read_bytes()).decode()))
        # Do not leave static feed bytes that a provider fail-open quota fallback
        # or a normalized alternate asset path could expose without the gate.
        target.unlink()
        # Public state is essential: hiding it would make revision 1 look like
        # an unconfigured bootstrap to another build and allow history erasure.
        routes.write_text(json.dumps({'version': 1, 'include': ['/updates/macos/*'], 'exclude': ['/updates/macos/state.json']}, indent=2)+'\n')
    else:
        for path in (worker, routes):
            path.unlink(missing_ok=True)


def signing_tools(directory, account, expected_key):
    artifacts.public_key(expected_key, required=True)
    artifacts.dependency(directory, os.environ.get('SPARKLE_ARCHIVE') or None)
    # -p only reads the existing public half. Never call key generation or export.
    key = subprocess.check_output([str(directory / 'bin/generate_keys'), '--account', account, '-p'], text=True, timeout=30).strip()
    if key != expected_key:
        raise ValueError('Existing Keychain public key differs from SPARKLE_PUBLIC_ED_KEY')
    return directory / 'bin/sign_update'


def sign_feed(output, catalog, withdrawals, directory, account, base_revision, base_feed, qualification=None):
    if output.exists():
        raise ValueError('Candidate output must be a new directory')
    retired = validate_catalog(catalog, withdrawals)
    key = os.environ.get('SPARKLE_PUBLIC_ED_KEY')
    tool = signing_tools(directory, account, key)
    rss = XML.Element('rss', {'version':'2.0', 'xmlns:sparkle': SPARKLE[1:-1], 'xmlns:estrobo': ESTROBO[1:-1]})
    channel = XML.SubElement(rss, 'channel')
    XML.SubElement(channel, 'title').text = 'Estrobo macOS updates'
    if qualification:
        validate_qualification(qualification, catalog, active=True)
        XML.SubElement(channel, 'estrobo:qualification').text = policy_text(qualification)
    for offer in sorted(catalog['offers'], key=lambda offer:int(offer['build']), reverse=True):
        item = XML.SubElement(channel, 'item')
        XML.SubElement(item, 'title').text = offer['version']
        XML.SubElement(item, 'description').text = offer['releaseNotes']['en']
        XML.SubElement(item, 'estrobo:releaseNotesEn').text = offer['releaseNotes']['en']
        XML.SubElement(item, 'estrobo:releaseNotesEs').text = offer['releaseNotes']['es']
        for name, value in [('version',offer['build']), ('shortVersionString',offer['version']), ('minimumSystemVersion',offer['minimumMacOSVersion'])]:
            XML.SubElement(item, 'sparkle:'+name).text = str(value)
        if offer['channel'] == 'beta':
            XML.SubElement(item, 'sparkle:channel').text = 'beta'
        XML.SubElement(item, 'enclosure', {'url':offer['archive']['url'], 'length':str(offer['archive']['length']), 'sparkle:edSignature':offer['archive']['edSignature'], 'type':'application/octet-stream'})
    output.mkdir(parents=True)
    feed = output / 'appcast.xml'
    feed.write_bytes(XML.tostring(rss, encoding='utf-8', xml_declaration=True))
    subprocess.run([str(tool), '--account', account, str(feed)], check=True, timeout=30)
    subprocess.run([str(tool), '--account', account, '--verify', str(feed)], check=True, timeout=30)
    (output / 'catalog.json').write_text(json.dumps(catalog, indent=2)+'\n')
    (output / 'withdrawals.json').write_text(json.dumps(withdrawals, indent=2)+'\n')
    approval = {'schemaVersion':1, 'state':'candidate', 'baseRevision':base_revision, 'baseFeedSHA256':base_feed,
                'publicKey':key, 'verifiedWith':'Sparkle 2.10.0 sign_update', 'feedSHA256':sha(feed),
                'catalogSHA256':sha(output / 'catalog.json'), 'withdrawalsSHA256':sha(output / 'withdrawals.json')}
    if qualification:
        approval['qualification'] = qualification
    (output / 'candidate.json').write_text(json.dumps(approval, indent=2)+'\n')
    validate_feed(feed, catalog, qualification)
    print(f'Signed local candidate only: {output}; feed SHA-256 {approval["feedSHA256"]}')


def source_state(source):
    approval = read_json(source / 'approval.json')
    if approval['state'] == 'approved':
        validate_approved(source)
        return approval['revision'], approval['feedSHA256']
    if approval['state'] != 'unconfigured' or read_json(source / 'catalog.json')['offers']:
        raise ValueError('Invalid previous approved source')
    return 0, None


def prepare(args, qualification=False):
    manifest = read_json(args.manifest)
    product, origin = manifest['product'], manifest['source']
    key = os.environ.get('SPARKLE_PUBLIC_ED_KEY')
    artifacts.public_key(key, required=True)
    channel = product['updateChannel']
    artifacts.validate_release_metadata(product['version'], product['build'], channel, origin['tag'])
    notes = {'en': args.notes_en.read_text(encoding='utf-8'), 'es': args.notes_es.read_text(encoding='utf-8')}
    validate_consumer_limits(args.archive.stat().st_size, notes)
    if not qualification and read_json(args.source / 'approval.json').get('qualification'):
        raise ValueError('Withdraw the qualification offer before preparing a public release')
    # Reuse the canonical final-approval verifier, preserving source/CI/notary/
    # exact tuple and physical smoke requirements. Catalog signing adds no authority.
    environment = dict(os.environ, DMG=str(args.archive.resolve()), MANIFEST=str(args.manifest.resolve()), CHECKSUMS=str(args.checksums.resolve()),
                       VERSION=product['version'], BUILD_NUMBER=product['build'], TAG=origin['tag'], COMMIT=origin['commit'], UPDATE_CHANNEL=channel,
                       BUNDLE_IDENTIFIER='mx.loo.estrobo', MACOSX_DEPLOYMENT_TARGET=product['minimumMacOSVersion'],
                       DEVELOPER_ID_TEAM_ID=manifest['signing']['teamIdentifier'],
                       DEVELOPER_ID_CERTIFICATE=str(ROOT / 'release/signing/estrobo-developer-id-application.cer'),
                       DEVELOPER_ID_CERTIFICATE_SHA256=str(ROOT / 'release/signing/estrobo-developer-id-application.sha256'),
                       APP_VERIFY_SCRIPT=str(ROOT / 'scripts/verify-macos-developer-id-release.sh'),
                       DMG_VERIFY_SCRIPT=str(ROOT / 'scripts/verify-macos-developer-id-dmg.sh'),
                       APPROVED_TAG=origin['tag'], APPROVED_COMMIT=origin['commit'], APPROVED_DMG_SHA256=manifest['artifact']['sha256'], PHYSICAL_SMOKE_STATUS='passed')
    policy = None
    if qualification:
        # An isolated production-identity test is deliberately separate from
        # release approval. Never manufacture a passed physical smoke.
        if channel != 'beta' or manifest['verification']['physicalSmoke'] != 'pending' or 'localReleaseApproval' in manifest['verification']:
            raise ValueError('Qualification requires an honestly pending beta candidate')
        receipt = args.authorization
        if receipt.stat().st_uid != os.getuid() or receipt.stat().st_mode & 0o077:
            raise ValueError('Qualification authorization must be an owner-only local file')
        policy = read_json(receipt)
        if policy.get('commit') != origin['commit'] or policy.get('dmgSHA256') != manifest['artifact']['sha256']:
            raise ValueError('Qualification authorization names different source/archive bytes')
        policy['authorizationSHA256'] = sha(receipt)
        if subprocess.check_output(['/usr/bin/git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip() != origin['commit']:
            raise ValueError('Qualification manifest source differs from the verified checkout')
        environment.pop('PHYSICAL_SMOKE_STATUS')
        subprocess.run([str(ROOT / 'scripts/verify-local-developer-id-release-source.sh')], env=environment, check=True)
        subprocess.run([str(ROOT / 'scripts/verify-macos-developer-id-dmg.sh')], env=environment, check=True)
    else:
        subprocess.run([str(ROOT / 'scripts/finalize-local-developer-id-release-approval.sh'), 'verify'], env=environment, check=True)
    if sha(args.archive) != manifest['artifact']['sha256'] or args.archive.stat().st_size != manifest['artifact']['sizeBytes']:
        raise ValueError('Final DMG bytes changed after approval')
    tool = signing_tools(args.sparkle_dir, args.account, key)
    signature = subprocess.check_output([str(tool), '--account', args.account, '-p', str(args.archive)], text=True, timeout=30).strip()
    subprocess.run([str(tool), '--account', args.account, '--verify', str(args.archive), signature], check=True, timeout=30)
    catalog = read_json(args.source / 'catalog.json')
    withdrawals = read_json(args.source / 'withdrawals.json')
    offer = {'build':product['build'], 'version':product['version'], 'channel':channel, 'tag':origin['tag'],
             'minimumMacOSVersion':product['minimumMacOSVersion'], 'architectures':product['architectures'], 'releaseNotes':notes,
             'manifestSHA256':sha(args.manifest),
             'archive':{'url':f"https://github.com/loomitz/estrobo/releases/download/{origin['tag']}/{args.archive.name}",
                        'length':args.archive.stat().st_size, 'sha256':sha(args.archive), 'edSignature':signature}}
    if any(str(existing['build']) == str(offer['build']) for existing in catalog['offers']):
        raise ValueError('Build already assigned in the immutable catalog; allocate a higher build')
    catalog['offers'].append(offer)
    revision, feed = source_state(args.source)
    sign_feed(args.output, catalog, withdrawals, args.sparkle_dir, args.account, revision, feed, policy)


def withdraw(args):
    revision, feed = source_state(args.source)
    if not revision:
        raise ValueError('Cannot withdraw from an unconfigured feed')
    catalog = read_json(args.source / 'catalog.json')
    withdrawals = read_json(args.source / 'withdrawals.json')
    if not any(str(offer['build']) == args.build for offer in catalog['offers']):
        raise ValueError('Withdrawn build is not an existing approved offer')
    catalog['offers'] = [offer for offer in catalog['offers'] if str(offer['build']) != args.build]
    withdrawals['withdrawals'].append({'build':args.build, 'reason':args.reason, 'withdrawnAt':datetime.datetime.now(datetime.timezone.utc).isoformat()})
    previous_policy = read_json(args.source / 'approval.json').get('qualification')
    sign_feed(args.output, catalog, withdrawals, args.sparkle_dir, args.account, revision, feed, previous_policy if catalog['offers'] else None)


def approve(args):
    candidate = read_json(args.candidate / 'candidate.json')
    revision, base_feed = source_state(args.source)
    if candidate['state'] != 'candidate' or candidate['baseRevision'] != revision or candidate['baseFeedSHA256'] != base_feed:
        raise ValueError('Candidate was based on a superseded approval')
    if candidate['feedSHA256'] != args.expected_feed_sha256:
        raise ValueError('Review must name the exact candidate feed digest')
    for name, field in [('appcast.xml','feedSHA256'), ('catalog.json','catalogSHA256'), ('withdrawals.json','withdrawalsSHA256')]:
        if sha(args.candidate / name) != candidate[field]:
            raise ValueError('Candidate digest changed after signing/review')
    catalog = read_json(args.candidate / 'catalog.json')
    withdrawals = read_json(args.candidate / 'withdrawals.json')
    retired = validate_catalog(catalog, withdrawals)
    previous_retired = {str(item['build']) for item in read_json(args.source / 'withdrawals.json')['withdrawals']}
    previous_records = read_json(args.source / 'withdrawals.json')['withdrawals']
    if withdrawals['withdrawals'][:len(previous_records)] != previous_records or not previous_retired.issubset(retired):
        raise ValueError('Withdrawal history is append-only')
    qualification = candidate.get('qualification')
    validate_feed(args.candidate / 'appcast.xml', catalog, qualification)
    if qualification:
        validate_qualification(qualification, catalog, active=True)
    key = os.environ.get('SPARKLE_PUBLIC_ED_KEY')
    if candidate['publicKey'] != key:
        raise ValueError('Candidate key differs from approved external root')
    tool = signing_tools(args.sparkle_dir, args.account, key)
    subprocess.run([str(tool), '--account', args.account, '--verify', str(args.candidate / 'appcast.xml')], check=True, timeout=30)
    # Approval happens after release publication: prove exact assets are anonymous.
    with tempfile.TemporaryDirectory(prefix='estrobo-public-update-verification-') as temporary:
        for offer in catalog['offers']:
            archive = pathlib.Path(temporary) / f"{offer['build']}.dmg"
            request = urllib.request.Request(offer['archive']['url'], headers={'Cache-Control':'no-cache', 'User-Agent':'EstroboCatalogVerifier/1.0'})
            with open_https(request, timeout=60) as response, archive.open('wb') as output:
                if not response.url.startswith('https://'):
                    raise ValueError('Anonymous archive redirected to insecure HTTP')
                shutil.copyfileobj(response, output)
            if archive.stat().st_size != offer['archive']['length'] or sha(archive) != offer['archive']['sha256']:
                raise ValueError('Anonymous release bytes differ from exact signed DMG')
            subprocess.run([str(tool), '--account', args.account, '--verify', str(archive), offer['archive']['edSignature']], check=True, timeout=30)
    # Preserve the previous approved source for audit/withdrawal history.
    history = args.source / 'history' / str(revision)
    if history.exists():
        raise ValueError('Previous revision archive already exists; inspect interrupted promotion')
    history.mkdir(parents=True)
    for name in ('appcast.xml','catalog.json','withdrawals.json','approval.json'):
        if (args.source / name).exists():
            shutil.copyfile(args.source / name, history / name)
    approval = dict(candidate, state='approved', revision=revision+1, approvedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
    for name in ('appcast.xml','catalog.json','withdrawals.json'):
        shutil.copyfile(args.candidate / name, args.source / name)
    (args.source / 'approval.json').write_text(json.dumps(approval, indent=2)+'\n')
    validate_approved(args.source)
    print(f'Approved local source revision {revision+1}. Review/commit it; deployment remains a separate action.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('site')
    build.add_argument('--source', type=pathlib.Path, default=ROOT / 'release/macos-updates')
    build.add_argument('--public', type=pathlib.Path, default=ROOT / 'website/public')
    build.add_argument('--published-state', type=pathlib.Path, help='Exact freshly retrieved public state, for offline build validation')
    for name in ('prepare', 'prepare-qualification', 'withdraw', 'approve'):
        command = commands.add_parser(name)
        command.add_argument('--source', type=pathlib.Path, default=ROOT / 'release/macos-updates')
        command.add_argument('--sparkle-dir', type=pathlib.Path, default=pathlib.Path(os.environ.get('SPARKLE_DIR', ROOT / '.build/Sparkle/2.10.0')))
        command.add_argument('--account', required=True, help='Existing maintainer Keychain signing account (no generation/export)')
        if name in ('prepare', 'prepare-qualification', 'withdraw'):
            command.add_argument('--output', type=pathlib.Path, required=True)
        if name in ('prepare', 'prepare-qualification'):
            for field in ('archive', 'manifest', 'checksums', 'notes-en', 'notes-es'):
                command.add_argument('--'+field, type=pathlib.Path, required=True)
        if name == 'prepare-qualification':
            command.add_argument('--authorization', type=pathlib.Path, required=True, help='Owner-only exact source/archive authorization, UTC expiry within 48 hours; not final release approval')
        if name == 'withdraw':
            command.add_argument('--build', required=True)
            command.add_argument('--reason', required=True)
        if name == 'approve':
            command.add_argument('--candidate', type=pathlib.Path, required=True)
            command.add_argument('--expected-feed-sha256', required=True)
    args = parser.parse_args()
    if args.command == 'site':
        site(args.source, args.public, args.published_state)
    elif args.command == 'prepare':
        prepare(args)
    elif args.command == 'prepare-qualification':
        prepare(args, qualification=True)
    elif args.command == 'withdraw':
        withdraw(args)
    elif args.command == 'approve':
        approve(args)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, XML.ParseError, subprocess.CalledProcessError) as error:
        print(f'macOS update catalog rejected: {error}', file=sys.stderr)
        sys.exit(1)
