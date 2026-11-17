#!/usr/bin/env python3
"""Build the local TV prototype with official Android SDK tools, JDK 17+ and an external debug key."""
import argparse,os,subprocess,shutil,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--android-jar',type=Path,required=True);p.add_argument('--build-tools',type=Path,required=True);p.add_argument('--java-home',type=Path,required=True);p.add_argument('--keystore',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parent;b=r/'.build';b.mkdir(exist_ok=True)
for name in ('compiled','generated','classes','dex'):
 if (b/name).exists():shutil.rmtree(b/name)
 (b/name).mkdir()
env=dict(os.environ,JAVA_HOME=str(a.java_home.resolve()),PATH=str(a.java_home.resolve()/'bin')+os.pathsep+os.environ.get('PATH',''))
def run(args):subprocess.run([str(x) for x in args],env=env,check=True)
t=a.build_tools.resolve();jar=a.android_jar.resolve();java=a.java_home.resolve()/'bin'
run([t/'aapt2','compile','--dir',r/'res','-o',b/'compiled'])
flats=sorted((b/'compiled').glob('*.flat'))
run([t/'aapt2','link','-o',b/'base.apk','--manifest',r/'AndroidManifest.xml','-I',jar,'--java',b/'generated','--auto-add-overlay',*flats])
run([java/'javac','-source','8','-target','8','-Xlint:-options','-classpath',jar,'-d',b/'classes',*sorted((r/'src').rglob('*.java')),*sorted((b/'generated').rglob('*.java'))])
with zipfile.ZipFile(b/'classes.jar','w') as z:
 for f in sorted((b/'classes').rglob('*.class')):z.write(f,f.relative_to(b/'classes'))
run([t/'d8','--lib',jar,'--min-api','26','--output',b/'dex',b/'classes.jar'])
shutil.copy2(b/'base.apk',b/'unsigned.apk')
with zipfile.ZipFile(b/'unsigned.apk','a') as z:z.write(b/'dex/classes.dex','classes.dex')
run([t/'zipalign','-f','4',b/'unsigned.apk',b/'aligned.apk'])
a.output.parent.mkdir(parents=True,exist_ok=True)
run([t/'apksigner','sign','--ks',a.keystore.resolve(),'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',a.output.resolve(),b/'aligned.apk'])
run([t/'apksigner','verify','--verbose',a.output.resolve()]);run([t/'zipalign','-c','4',a.output.resolve()])
print('Built and verified local prototype:',a.output)
