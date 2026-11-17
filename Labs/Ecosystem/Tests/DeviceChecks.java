package ru.bushe.strokatv.lab;
import android.app.Instrumentation;
import android.os.Bundle;
import java.io.*;
import java.net.*;
import javax.net.ssl.*;
import java.security.*;
import java.security.cert.*;
import org.json.*;
import com.google.zxing.*;
import com.google.zxing.common.*;
import com.google.zxing.qrcode.*;
import java.util.*;

// Separate checks-only APK. Does not grant overlay permission, approve a controller or start playback.
public final class DeviceChecks extends Instrumentation {
    int checks;Engine engine;LinkServer server;
    public void onCreate(Bundle arguments){super.onCreate(arguments);start();}
    void check(boolean ok,String label)throws Exception{if(!ok)throw new Exception(label);checks++;}
    @Override public void onStart(){Bundle result=new Bundle();try{
        TVIdentity identity=new TVIdentity(getTargetContext());check(identity.fingerprint.matches("[a-f0-9]{64}"),"Keystore TLS identity");check(identity.open(identity.seal("isolated-test-value")).equals("isolated-test-value"),"Keystore encrypted storage");
        engine=new Engine(getTargetContext());server=new LinkServer(getTargetContext(),engine);String ip=MainActivity.localIP();check(ip!=null,"Private LAN address");String qr=server.ticket(ip);check(qr.startsWith("stroka://pair?v=2&"),"Pairing ticket");
        BitMatrix matrix=new QRCodeWriter().encode(qr,BarcodeFormat.QR_CODE,720,720);byte[] luminance=new byte[720*720];for(int y=0;y<720;y++)for(int x=0;x<720;x++)luminance[y*720+x]=(byte)(matrix.get(x,y)?0:255);
        com.google.zxing.Result decoded=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new PlanarYUVLuminanceSource(luminance,720,720,0,0,720,720,false))));check(decoded.getText().equals(qr),"Real QR roundtrip");
        String reply=request(ip,server.socket.getLocalPort(),identity,"GET","/profile",new JSONObject());check(reply.startsWith("HTTP/1.1 401"),"Unauthenticated read denied over actual TLS");
        reply=request(ip,server.socket.getLocalPort(),identity,"POST","/pair/request",new JSONObject().put("nonce",TVIdentity.random()).put("name","Fixture"));check(reply.startsWith("HTTP/1.1 403"),"Unknown QR nonce denied");
        server.approval=(name,code,approve,deny)->deny.run();
        String nonce=android.net.Uri.parse(qr).getQueryParameter("nonce");
        reply=request(ip,server.socket.getLocalPort(),identity,"POST","/pair/request",new JSONObject().put("nonce",nonce).put("name","Fixture"));check(reply.startsWith("HTTP/1.1 202"),"Valid QR enters pending state");
        JSONObject pending=new JSONObject(reply.substring(reply.indexOf("\r\n\r\n")+4));String request=pending.getString("request");
        reply=request(ip,server.socket.getLocalPort(),identity,"POST","/pair/request",new JSONObject().put("nonce",nonce).put("name","Fixture"));check(reply.startsWith("HTTP/1.1 403"),"Consumed QR cannot enroll another device");
        reply=request(ip,server.socket.getLocalPort(),identity,"POST","/pair/result",new JSONObject().put("request",request));check(reply.contains("denied"),"TV denial never returns a controller token");check(server.tokens.isEmpty(),"No controller grant");
        java.util.List<FeedParser.Entry> entries=FeedParser.parse("<rss><channel><item><title>Headline</title><pubDate>Fri, 15 Jan 2027 07:59:00 GMT</pubDate></item></channel></rss>".getBytes("UTF-8"));check(entries.size()==1&&entries.get(0).published>0,"Android SAX implementation");
        JSONObject profile=Engine.defaults();profile.getJSONArray("rows").getJSONObject(0).put("kind","message").put("messages",new JSONArray().put("Тест автономной строки"));int old=engine.revision();engine.save(profile);check(engine.revision()==old+1,"Profile revision");check(engine.render().getJSONArray("rows").getJSONObject(0).getJSONArray("items").length()==1,"Autonomous own-text render");
        engine.close();engine=new Engine(getTargetContext());check(engine.revision()==old+1&&engine.render().getJSONArray("rows").getJSONObject(0).getJSONArray("items").length()==1,"Atomic profile survives engine restart");
        check(!TickerService.running,"No overlay service started by tests");result.putString("stream","PASS "+checks+" physical Android TV checks: Keystore, TLS, QR, denial, SAX, persistence; no overlay permission or controller grant\n");finish(-1,result);
    }catch(Exception error){result.putString("stream","FAIL after "+checks+": "+error.getClass().getSimpleName()+" "+error.getMessage()+" server="+(server==null?"not started":server.failureClass)+"\n");finish(0,result);}finally{if(server!=null)server.close();if(engine!=null)engine.close();}}
    String request(String ip,int port,TVIdentity identity,String method,String path,JSONObject body)throws Exception {
        SSLContext tls=SSLContext.getInstance("TLS");tls.init(null,new TrustManager[]{new X509TrustManager(){public X509Certificate[] getAcceptedIssuers(){return new X509Certificate[0];}public void checkClientTrusted(X509Certificate[] chain,String auth)throws CertificateException{throw new CertificateException();}public void checkServerTrusted(X509Certificate[] chain,String auth)throws CertificateException{try{if(!TVIdentity.hex(MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded())).equals(identity.fingerprint))throw new CertificateException();}catch(Exception e){throw new CertificateException(e);}}}},null);
        try(SSLSocket socket=(SSLSocket)tls.getSocketFactory().createSocket(ip,port)){socket.setSoTimeout(5000);socket.startHandshake();byte[] bytes=body.toString().getBytes("UTF-8");OutputStream out=socket.getOutputStream();out.write((method+" "+path+" HTTP/1.1\r\nHost: stroka.local\r\nContent-Length: "+bytes.length+"\r\nConnection: close\r\n\r\n").getBytes("US-ASCII"));out.write(bytes);out.flush();return new String(Engine.read(socket.getInputStream(),524288),"UTF-8");}
    }
}
