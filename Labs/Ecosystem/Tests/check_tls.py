#!/usr/bin/env python3
"""Real TLS fixture, not a claimed Android/iOS acceptance test. Test private key stays in temporary storage."""
import tempfile,subprocess,ssl,socket,threading,http.server,hashlib,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
class Fixture(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,status,data,extra=0):
  self.send_response(status);self.send_header('Content-Length',str(len(data)+extra));self.end_headers();self.wfile.write(data);self.close_connection=True
 def do_GET(self):
  if self.headers.get('Authorization')!='Bearer '+'a'*64:self.reply(401,b'{}')
  elif self.path=='/malformed':self.reply(200,b'{}',1)
  else:self.reply(200,b'{"ok":true}')
 def do_PUT(self):
  self.rfile.read(int(self.headers.get('Content-Length','0')));self.reply(409,b'{}')
with tempfile.TemporaryDirectory(prefix='stroka-tls-fixture-') as temp:
 temp=pathlib.Path(temp)
 subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256','-nodes','-keyout',str(temp/'key.pem'),'-out',str(temp/'cert.pem'),'-subj','/CN=Stroka isolated test','-days','1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 cert=ssl.PEM_cert_to_DER_cert((temp/'cert.pem').read_text());pin=hashlib.sha256(cert).hexdigest()
 server=http.server.ThreadingHTTPServer(('0.0.0.0',0),Fixture);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ssl.TLSVersion.TLSv1_2;ctx.load_cert_chain(temp/'cert.pem',temp/'key.pem');server.socket=ctx.wrap_socket(server.socket,server_side=True)
 threading.Thread(target=server.serve_forever,daemon=True).start()
 ip=subprocess.check_output(['ipconfig','getifaddr','en0'],text=True).strip()
 try:subprocess.run([str(root/'Validation/link-checks'),ip,str(server.server_port),pin],check=True,timeout=30)
 finally:server.shutdown();server.server_close()
