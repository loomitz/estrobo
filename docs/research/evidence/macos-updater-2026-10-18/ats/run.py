import pathlib,plistlib,subprocess,os,json,urllib.request,tempfile
root=pathlib.Path(__file__).resolve().parent
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer')
source=pathlib.Path('/Users/loomitz/Dev/estrobo-macos-auto-update/prototype/EstroboMac/Info.plist')
public_fixture=pathlib.Path('/var/folders/1y/8thwntgj3gxfv6s4qbfn5pr40000gn/T/estrobo-consent-spike-jlykscjv/build1/ConsentSpike.app/Contents/Info.plist')
public_key=plistlib.loads(public_fixture.read_bytes())['SUPublicEDKey']
base=pathlib.Path(tempfile.mkdtemp(prefix='estrobo-ats-runtime-'))
results=[]
cases={'external-http':'http://example.com/','external-https-control':'https://example.com/','https-to-http-redirect':'https://httpbingo.org/redirect-to?url=http%3A%2F%2Fexample.com%2F'}
for name,url in cases.items():
 app=base/name/'ATSHost.app'; (app/'Contents/MacOS').mkdir(parents=True); (app/'Contents/Frameworks').mkdir()
 subprocess.run(['ditto',str(root/'ATSHost'),str(app/'Contents/MacOS/ATSHost')],check=True)
 subprocess.run(['ditto','/private/tmp/estrobo-updater-consent-research/Sparkle.framework',str(app/'Contents/Frameworks/Sparkle.framework')],check=True)
 info=plistlib.loads(source.read_bytes()); assert 'NSAppTransportSecurity' not in info
 info.update({'CFBundleIdentifier':'mx.loo.estrobo.ats-fixture.'+name,'CFBundleName':'ATSHost','CFBundleExecutable':'ATSHost','CFBundleVersion':'1','CFBundleShortVersionString':'0.0.1','SUPublicEDKey':public_key,'SUFeedURL':url,'SUEnableAutomaticChecks':False,'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':False,'SUEnableInstallerLauncherService':False,'SUEnableSystemProfiling':False,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'SUSignedFeedFailureExpirationInterval':0})
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True,capture_output=True)
 try:
  result=subprocess.run([str(app/'Contents/MacOS/ATSHost')],env=env,capture_output=True,text=True,timeout=30)
  record={'case':name,'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'app':str(app)}
 except subprocess.TimeoutExpired as e: record={'case':name,'timeout':True,'stdout':str(e.stdout),'stderr':str(e.stderr),'app':str(app)}
 results.append(record)
 print(json.dumps(record),flush=True)
(root/'runtime-results.json').write_text(json.dumps(results,indent=2))
(root/'environment.json').write_text(json.dumps({'appInfoSource':str(source),'sourceATSAbsent':True,'os':subprocess.check_output(['sw_vers'],text=True),'toolchain':subprocess.check_output(['xcrun','swiftc','--version'],text=True,env=env),'fixtureRoot':str(base)},indent=2))
