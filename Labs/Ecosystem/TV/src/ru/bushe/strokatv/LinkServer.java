package ru.bushe.strokatv.lab;

import android.content.*;
import android.os.*;
import android.net.nsd.*;
import org.json.*;
import java.net.*;
import javax.net.ssl.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

final class LinkServer {
    interface Approval {void requested(String name,String challenge,Runnable approve,Runnable deny);}
    final Context context;final TVIdentity identity;final Engine engine;
    final Handler main=new Handler(Looper.getMainLooper());
    final ThreadPoolExecutor clients=new ThreadPoolExecutor(0,4,15,TimeUnit.SECONDS,new SynchronousQueue<>());
    volatile boolean closed=false;volatile Approval approval;
    volatile String failureClass="";
    SSLServerSocket socket;NsdManager nsd;NsdManager.RegistrationListener registration;
    String nonce="";long expires;Pending pending;int attempts;long attemptWindow;
    final HashMap<String,Long> tokens=new HashMap<>();
    static final class Pending {String id,challenge,name,token;long expiry;boolean approved,denied;}
    LinkServer(Context c,Engine engineValue)throws Exception {
        context=c.getApplicationContext();engine=engineValue;identity=new TVIdentity(context);
        try{JSONObject saved=new JSONObject(identity.open(context.getSharedPreferences("v2",0).getString("controllers","")));for(Iterator<String> it=saved.keys();it.hasNext();){String key=it.next();tokens.put(key,saved.getLong(key));}}catch(Exception ignored){}
        socket=(SSLServerSocket)identity.tls.getServerSocketFactory().createServerSocket(0,8,InetAddress.getByName("0.0.0.0"));
        socket.setEnabledProtocols(new String[]{"TLSv1.2"});
        Thread accept=new Thread(()->{while(!closed)try{SSLSocket s=(SSLSocket)socket.accept();if(!ProfileRules.privatePeer(s.getInetAddress())){s.close();continue;}s.setSoTimeout(5000);try{clients.execute(()->serve(s));}catch(RejectedExecutionException full){s.close();}}catch(IOException e){if(!closed)close();}},"stroka-tv-link");accept.setDaemon(true);accept.start();
        nsd=(NsdManager)context.getSystemService(Context.NSD_SERVICE);NsdServiceInfo info=new NsdServiceInfo();info.setServiceName(service());info.setServiceType("_stroka._tcp.");info.setPort(socket.getLocalPort());info.setAttribute("id",identity.id);info.setAttribute("v","2");
        registration=new NsdManager.RegistrationListener(){public void onServiceRegistered(NsdServiceInfo i){}public void onRegistrationFailed(NsdServiceInfo i,int e){}public void onServiceUnregistered(NsdServiceInfo i){}public void onUnregistrationFailed(NsdServiceInfo i,int e){}};
        nsd.registerService(info,NsdManager.PROTOCOL_DNS_SD,registration);
    }
    String service(){return "Stroka-TV-"+identity.id;}
    synchronized String ticket(String ip)throws Exception {
        if(!ProfileRules.privatePeer(InetAddress.getByName(ip)))throw new Exception("Private Wi-Fi required");
        nonce=TVIdentity.random();expires=SystemClock.elapsedRealtime()+120000;pending=null;
        return "stroka://pair?v=2&host="+ip+"&port="+socket.getLocalPort()+"&fp="+identity.fingerprint+"&nonce="+nonce+"&id="+identity.id+"&service="+service()+"&exp="+((System.currentTimeMillis()+120000)/1000.0);
    }
    void serve(SSLSocket s){try(SSLSocket link=s){link.startHandshake();InputStream in=link.getInputStream();ByteArrayOutputStream header=new ByteArrayOutputStream();int b;String text="";
        while((b=in.read())!=-1){header.write(b);if(header.size()>8192)throw new IOException();byte[] x=header.toByteArray();int n=x.length;if(n>=4&&x[n-4]==13&&x[n-3]==10&&x[n-2]==13&&x[n-1]==10){text=new String(x,StandardCharsets.US_ASCII);break;}}
        String[] lines=text.split("\r\n"),request=lines[0].split(" ");if(request.length!=3)throw new IOException();String method=request[0],path=request[1],auth="";int length=0;boolean hasLength=false;
        for(int i=1;i<lines.length;i++){int at=lines[i].indexOf(':');if(at<0)continue;String key=lines[i].substring(0,at).toLowerCase(Locale.ROOT),value=lines[i].substring(at+1).trim();if(key.equals("content-length")){if(hasLength)throw new IOException();hasLength=true;length=Integer.parseInt(value);}if(key.equals("authorization"))auth=value;if(key.equals("transfer-encoding"))throw new IOException();}
        if(length<0||length>262144)throw new IOException();byte[] bytes=new byte[length];int offset=0;while(offset<length){int n=in.read(bytes,offset,length-offset);if(n<0)throw new IOException();offset+=n;}
        JSONObject body=length==0?new JSONObject():new JSONObject(new String(bytes,StandardCharsets.UTF_8));Reply reply=route(method,path,auth,body);byte[] data=reply.value.toString().getBytes(StandardCharsets.UTF_8);
        OutputStream out=link.getOutputStream();out.write(("HTTP/1.1 "+reply.status+" Response\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: "+data.length+"\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));out.write(data);out.flush();
    }catch(Exception ignored){failureClass=ignored.getClass().getSimpleName();if(ignored instanceof SSLException){failureClass+=" key-type="+identity.requestedKeyType+" "+ignored.getMessage();}/* No request body, key, or QR contents in logs. */}}
    static final class Reply {int status;JSONObject value;Reply(int s,JSONObject v){status=s;value=v;}}
    Reply error(int code)throws Exception{return new Reply(code,new JSONObject().put("error",code));}
    synchronized Reply route(String method,String path,String auth,JSONObject body)throws Exception {
        long now=SystemClock.elapsedRealtime();
        if(path.equals("/pair/request")&&method.equals("POST")){
            if(now-attemptWindow>60000){attemptWindow=now;attempts=0;}if(++attempts>8)return error(429);
            if(approval==null||now>=expires||nonce.isEmpty()||!MessageDigest.isEqual(nonce.getBytes(StandardCharsets.US_ASCII),body.optString("nonce").getBytes(StandardCharsets.US_ASCII)))return error(403);
            String name=body.optString("name").replaceAll("[\\p{Cntrl}]","");if(name.isEmpty()||name.length()>48)return error(400);
            nonce="";Pending p=new Pending();p.id=TVIdentity.random();p.name=name;p.challenge=String.format(Locale.ROOT,"%06d",new java.security.SecureRandom().nextInt(1000000));p.expiry=now+120000;pending=p;
            main.post(()->{Approval a=approval;if(a!=null)a.requested(p.name,p.challenge,()->approve(p),()->{synchronized(LinkServer.this){p.denied=true;}});});
            return new Reply(202,new JSONObject().put("request",p.id).put("challenge",p.challenge));
        }
        if(path.equals("/pair/result")&&method.equals("POST")){
            Pending p=pending;if(p==null||now>=p.expiry||!MessageDigest.isEqual(p.id.getBytes(StandardCharsets.US_ASCII),body.optString("request").getBytes(StandardCharsets.US_ASCII)))return error(403);
            if(p.denied)return new Reply(200,new JSONObject().put("state","denied"));
            if(!p.approved)return new Reply(200,new JSONObject().put("state","pending"));
            // Re-deliver during this short session after a dropped response; never issue another token.
            return new Reply(200,new JSONObject().put("state","approved").put("token",p.token).put("id",identity.id).put("name","Stroka TV"));
        }
        if(!authorized(auth))return error(401);
        if(path.equals("/profile")&&method.equals("GET"))return new Reply(200,engine.document());
        if(path.equals("/profile")&&method.equals("PUT")){
            if(body.getInt("revision")!=engine.revision())return error(409);
            JSONObject profile;try{profile=ProfileRules.validate(body.getJSONObject("profile"));}catch(Exception invalid){return error(422);}
            engine.save(profile);return new Reply(200,engine.document());
        }
        if(path.equals("/device/revoke")&&method.equals("POST")){String hash=hash(auth.substring(7));tokens.remove(hash);persistTokens();return new Reply(200,new JSONObject().put("ok",true));}
        return error(404);
    }
    synchronized void approve(Pending p){if(p!=pending||SystemClock.elapsedRealtime()>=p.expiry||p.denied)return;try{
        if(tokens.size()>=8){p.denied=true;return;}p.token=TVIdentity.random();tokens.put(hash(p.token),System.currentTimeMillis());persistTokens();p.approved=true;
        Intent intent=new Intent(context,TickerService.class);context.startForegroundService(intent);
    }catch(Exception e){tokens.remove(hashQuiet(p.token));p.token=null;p.approved=false;p.denied=true;try{persistTokens();}catch(Exception ignored){}}}
    String hash(String token)throws Exception{return TVIdentity.hex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.US_ASCII)));}
    String hashQuiet(String token){try{return hash(token);}catch(Exception e){return "";}}
    boolean authorized(String auth)throws Exception{return auth.matches("Bearer [a-f0-9]{64}")&&tokens.containsKey(hash(auth.substring(7)));}
    void persistTokens()throws Exception{JSONObject x=new JSONObject();for(String h:tokens.keySet())x.put(h,tokens.get(h));if(!context.getSharedPreferences("v2",0).edit().putString("controllers",identity.seal(x.toString())).commit())throw new IOException();}
    synchronized void revokeAll(){tokens.clear();pending=null;nonce="";try{persistTokens();}catch(Exception ignored){}}
    void close(){closed=true;try{socket.close();}catch(Exception ignored){}clients.shutdownNow();try{nsd.unregisterService(registration);}catch(Exception ignored){}}
}
