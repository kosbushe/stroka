#!/usr/bin/env python3
"""Generate a dependency-free, two-target Xcode project. No signing team is selected."""
from pathlib import Path
import plistlib,shutil,hashlib
r=Path(__file__).resolve().parent
shared=sorted((r/'Shared').glob('*.swift'));apple=sorted((r/'Apple').glob('*.swift'));sources=shared+apple
resources=[r/'Resources/NewsCatalog.json',r/'Apple/PrivacyInfo.xcprivacy']
base={'CFBundleDevelopmentRegion':'ru','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.1','CFBundleVersion':'2','NSLocalNetworkUsageDescription':'Stroka подключается к вашему телевизору по домашней сети для выбора и запуска ленты.','NSBonjourServices':['_stroka._tcp'],'CFBundleURLTypes':[{'CFBundleURLSchemes':['stroka']}], 'NSCameraUsageDescription':'Камера нужна только для сканирования QR подключения на телевизоре.'}
ios=dict(base,LSRequiresIPhoneOS=True,UILaunchScreen={},UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
mac=dict(base,LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)
for name,d in [('iOS',ios),('Mac',mac)]:
 with (r/f'Apple/Info-{name}.plist').open('wb') as f:plistlib.dump(d,f)
privacy={'NSPrivacyTracking':False,'NSPrivacyCollectedDataTypes':[],'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']}]}
with (r/'Apple/PrivacyInfo.xcprivacy').open('wb') as f:plistlib.dump(privacy,f)
ent={'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.files.user-selected.read-only':True}
with (r/'Apple/Stroka-Link.entitlements').open('wb') as f:plistlib.dump(ent,f)
def uid(s):return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
def q(s):return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
objects=[]
def obj(key,value):objects.append(uid(key)+' = '+value+';')
fileIDs=[]
for f in sources+resources:
 rel=str(f.relative_to(r));fileIDs.append(uid(rel));typ='sourcecode.swift' if f.suffix=='.swift' else 'text.json' if f.suffix=='.json' else 'text.xml'
 obj(rel,'{isa = PBXFileReference; lastKnownFileType = '+typ+'; path = '+q('../'+rel)+'; sourceTree = "<group>";}')
products=[];targets=[]
for kind in ['iOS','Mac']:
 name='Stroka iPhone Lab' if kind=='iOS' else 'Stroka Link Lab';t='target-'+kind;targets.append(uid(t));product='product-'+kind;products.append(uid(product))
 obj(product,'{isa = PBXFileReference; explicitFileType = wrapper.application; path = '+q(name+'.app')+'; sourceTree = BUILT_PRODUCTS_DIR;}')
 for phase,files in [('sources',sources),('resources',resources)]:
  build=[]
  for f in files:
   rel=str(f.relative_to(r));bid=kind+'-'+rel;build.append(uid(bid));obj(bid,'{isa = PBXBuildFile; fileRef = '+uid(rel)+';}')
  obj(kind+'-'+phase,'{isa = PBX'+('Sources' if phase=='sources' else 'Resources')+'BuildPhase; buildActionMask = 2147483647; files = ('+','.join(build)+'); runOnlyForDeploymentPostprocessing = 0;}')
 obj(t,'{isa = PBXNativeTarget; buildConfigurationList = '+uid(kind+'-configlist')+'; buildPhases = ('+uid(kind+'-sources')+','+uid(kind+'-resources')+'); buildRules = (); dependencies = (); name = '+q(name)+'; productName = '+q(name)+'; productReference = '+uid(product)+'; productType = "com.apple.product-type.application";}')
 configs=[]
 for mode in ['Debug','Release']:
  key=kind+'-'+mode;configs.append(uid(key));settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'ru.bushe.stroka.ecosystem.lab.'+kind.lower(),'INFOPLIST_FILE':'../Apple/Info-'+kind+'.plist','SWIFT_VERSION':'5.0','CODE_SIGN_STYLE':'Automatic','ENABLE_HARDENED_RUNTIME':'YES','GENERATE_INFOPLIST_FILE':'NO','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','SDKROOT':'iphoneos' if kind=='iOS' else 'macosx'}
  if kind=='iOS':settings.update({'IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator'})
  else:settings.update({'MACOSX_DEPLOYMENT_TARGET':'14.0','CODE_SIGN_ENTITLEMENTS':'../Apple/Stroka-Link.entitlements'})
  obj(key,'{isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+q(v)+';' for k,v in settings.items())+'}; name = '+mode+';}')
 obj(kind+'-configlist','{isa = XCConfigurationList; buildConfigurations = ('+','.join(configs)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
obj('group','{isa = PBXGroup; children = ('+','.join(fileIDs+[uid('products')])+'); sourceTree = "<group>";}')
obj('products','{isa = PBXGroup; children = ('+','.join(products)+'); name = Products; sourceTree = "<group>";}')
for mode in ['Debug','Release']:obj('project-'+mode,'{isa = XCBuildConfiguration; buildSettings = {}; name = '+mode+';}')
obj('project-list','{isa = XCConfigurationList; buildConfigurations = ('+uid('project-Debug')+','+uid('project-Release')+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
obj('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = '+uid('project-list')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru,en,Base); mainGroup = '+uid('group')+'; productRefGroup = '+uid('products')+'; projectDirPath = ""; projectRoot = ""; targets = ('+','.join(targets)+');}')
p=r/'Apple/Stroka Ecosystem.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
# Project paths are relative to Apple/, not .xcodeproj/.
print(p)
