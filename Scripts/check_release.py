#!/usr/bin/env python3
"""Validate source packaging metadata. Publication checks are a separate, stricter mode."""
from pathlib import Path
import json,plistlib,re,sys,urllib.parse
r=Path(__file__).resolve().parents[1]
def require(ok,message):
    if not ok:raise SystemExit('FAIL: '+message)
    print('PASS: '+message)
require(all((r/name).is_file() for name in ('CONSTITUTION.md','Docs/PRODUCT-DESCRIPTION.md','Docs/PROJECT-BRIEF.md')), 'project constitution, description and brief included')
info=plistlib.loads((r/'Info.plist').read_bytes());ent=plistlib.loads((r/'Stroka.entitlements').read_bytes());privacy=plistlib.loads((r/'PrivacyInfo.xcprivacy').read_bytes())
require(info['CFBundleDevelopmentRegion']=='en' and info['CFBundleLocalizations']==['en','ru'],'English primary and Russian secondary')
require(info['LSMinimumSystemVersion']=='14.0','macOS deployment floor declared')
require(ent.get('com.apple.security.app-sandbox') is True,'sandbox enabled')
require(not ent.get('com.apple.security.get-task-allow',False),'release entitlements exclude debugger access')
require('StrokaDiagnostics' not in info,'production metadata excludes diagnostic entry points')
require(privacy['NSPrivacyTracking'] is False and not privacy['NSPrivacyTrackingDomains'],'no tracking declared')
reasons={x['NSPrivacyAccessedAPIType']:x['NSPrivacyAccessedAPITypeReasons'] for x in privacy['NSPrivacyAccessedAPITypes']}
require(reasons.get('NSPrivacyAccessedAPICategoryUserDefaults')==['CA92.1'] and reasons.get('NSPrivacyAccessedAPICategorySystemBootTime')==['35F9.1'],'local preferences and timing reason declarations present')
cat=json.loads((r/'Resources/Localizable.xcstrings').read_text())
require(cat['sourceLanguage']=='en' and all(set(x['localizations'])>={'en','ru'} for x in cat['strings'].values()),'every String Catalog entry has English and Russian')
for name in ('SavedSettings.swift','ControlView.swift','TelegramSource.swift','TVBridge.swift','QuickFeed.swift','Onboarding.swift','SimpleSetup.swift','TickerRows.swift','MarketCatalog.swift','FeedChooser.swift'):
    keys=set(re.findall(r'\bL\("([^"\\]*)"\)',(r/'Sources'/name).read_text()))
    require(not (keys-set(cat['strings'])),name+' literal UI strings exist in the catalog')
project=(r/'Stroka.xcodeproj/project.pbxproj').read_text()
require(all('path = '+x.name+';' in project for x in (r/'Sources').glob('*.swift')),'all production Swift sources are referenced in the Xcode project')
feeds=json.loads((r/'Resources/NewsCatalog.json').read_text())
require(len(feeds)==550 and len({x['id'] for x in feeds})==len(feeds) and len({x['url'] for x in feeds})==len(feeds),'550 catalog entries with unique identities and URLs')
require(all(sum(x['category']==category for x in feeds)==50 for category in ('world','business','moscow','technology','ai','science','space','culture','cinema','sport','environment')),'every news topic has 50 entries with historical check metadata')
require(all(urllib.parse.urlparse(x['url']).scheme=='https' and urllib.parse.urlparse(x['url']).hostname for x in feeds),'catalog feeds use HTTPS')
collections=json.loads((r/'Resources/Collections.json').read_text())
require(sum(map(len,collections.values()))==96,'96 original bilingual offline items')
for language in ('en','ru'):
    for filename in ('Localizable.stringsdict','InfoPlist.strings'):
        file=r/'Resources'/f'{language}.lproj'/filename
        if file.exists() and file.suffix=='.stringsdict':plistlib.loads(file.read_bytes())
require((r/'AppIcon.icns').is_file() and (r/'Icon1024.png').is_file(),'app and store icon source included')
# Read source only. Do not scan settings/caches or print potential credential values.
patterns=[r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',r'gh[pousr]_[A-Za-z0-9]{30,}',r'github_pat_[A-Za-z0-9_]{30,}',r'AKIA[0-9A-Z]{16}']
violations=[]
for folder in ('Sources','Resources','Tests','StoreMetadata','Docs','Scripts','.github','TVCompanion'):
    for file in (r/folder).rglob('*'):
        if any(part in ('.build','build','.gradle','__pycache__') for part in file.relative_to(r).parts):continue
        if file.is_file() and file.suffix in ('.swift','.json','.txt','.html','.xcstrings','.strings','.md','.py','.zsh','.yml','.kt','.kts','.xml'):
            text=file.read_text(errors='replace')
            if any(re.search(pattern,text) for pattern in patterns):violations.append(str(file.relative_to(r)))
require(not violations,'no matching common credential patterns in distributable text sources')
if '--publication' in sys.argv:
    config=json.loads((r/'StoreMetadata/Publication.json').read_text())
    for name in ('support_url','privacy_url'):
        u=urllib.parse.urlparse(config[name]);require(u.scheme=='https' and bool(u.hostname),name+' configured')
    require(bool(config['source_terms']),'owner source-distribution terms selected')
    require(bool(config['developer_team']),'developer team selected')
    require(config['provider_permissions_reviewed'] is True,'provider permissions reviewed')
    require(config['device_acceptance_complete'] is True,'device acceptance completed')
    print('Metadata gates passed; Xcode signing, archive/upload validation and App Review remain separate.')
else:print('Technical source checks passed. Public release gates are separate; use --publication for owner metadata checks.')
