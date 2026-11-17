#!/usr/bin/env python3
"""Explicit live source check. Uses curl with decompression and the app's native parser."""
from pathlib import Path
import argparse,base64,concurrent.futures,datetime,hashlib,json,plistlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--app',required=True,type=Path);p.add_argument('--all',action='store_true',help='check all 550 feeds instead of two per topic');p.add_argument('--output',required=True,type=Path);a=p.parse_args()
r=Path(__file__).resolve().parents[1];app=a.app.resolve();info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
if info.get('StrokaDiagnostics') is not True:raise SystemExit('Build with STROKA_DIAGNOSTICS=1 before using this checker.')
feeds=json.loads((r/'Resources/NewsCatalog.json').read_text());selected=[];counts={}
for feed in feeds:
 cat=feed['category'];counts[cat]=counts.get(cat,0)+1
 if a.all or counts[cat]<=2:selected.append(feed)
ua='Stroka/'+info['CFBundleShortVersionString']+' macOS RSS reader';now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
with tempfile.TemporaryDirectory(prefix='stroka-source-check-') as temp:
 folder=Path(temp)
 def fetch(feed):
  file=folder/hashlib.sha256(feed['url'].encode()).hexdigest()
  proc=subprocess.run(['curl','--compressed','-sS','-L','--proto','=https','--proto-redir','=https','--max-time','20','--connect-timeout','7','--max-filesize','5000000','-A',ua,'-o',str(file),'-w','%{http_code}',feed['url']],capture_output=True,text=True)
  ok=proc.returncode==0 and proc.stdout.strip()=='200' and file.exists() and file.stat().st_size<=5_000_000
  return dict(id=feed['id'],name=feed['name'],url=feed['url'],category=feed['category'],language=feed['language'],http=proc.stdout.strip(),available=ok,checkedAtUTC=now())
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:records=list(pool.map(fetch,selected))
 successful=[x for x in records if x['available']];native={}
 for start in range(0,len(successful),20):
  batch=successful[start:start+20];payload=[]
  for item in batch:
   file=folder/hashlib.sha256(item['url'].encode()).hexdigest();payload.append(dict(name=item['name'],url=item['url'],language=item['language'],data=base64.b64encode(file.read_bytes()).decode()))
  proc=subprocess.run([str(app/'Contents/MacOS/Stroka'),'--feed-parser-check','--feed-health-audit'],input=json.dumps(payload).encode(),capture_output=True,timeout=60);proc.check_returncode()
  native.update({row['url']:row for row in json.loads(proc.stdout)})
 for item in records:item.update(native.get(item['url'],{}))
 result=dict(checkedAtUTC=now(),scope='all' if a.all else 'two per topic',sources=len(records),available=sum(x['available'] for x in records),readable=sum(x.get('parsed',0)>0 for x in records),withFreshNews=sum(x.get('fresh24h',0)>0 for x in records),records=records)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='records'},ensure_ascii=False))
