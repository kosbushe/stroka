package ru.bushe.strokatv.lab;

import android.content.*;
import android.util.AtomicFile;
import android.text.Html;
import org.json.*;
import org.xml.sax.*;
import org.xml.sax.helpers.DefaultHandler;
import javax.xml.parsers.*;
import javax.net.ssl.HttpsURLConnection;
import java.net.*;
import java.io.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.*;

// Autonomous source engine. Cached rows remain subject to original publication expiry.
final class Engine {
    final Context context;final AtomicFile file;final ScheduledExecutorService worker=Executors.newSingleThreadScheduledExecutor();
    JSONObject profile;int version;String status="Выберите источники на телефоне или Mac";
    final HashMap<String,JSONArray> stories=new HashMap<>();final HashMap<String,Long> fetched=new HashMap<>();
    Engine(Context c)throws Exception {
        context=c.getApplicationContext();file=new AtomicFile(new File(context.getFilesDir(),"station-v2.json"));
        try(InputStream in=file.openRead()){JSONObject d=new JSONObject(new String(read(in,262144),"UTF-8"));profile=ProfileRules.validate(d.getJSONObject("profile"));version=d.getInt("revision");}
        catch(Exception e){profile=defaults();version=0;}
        worker.scheduleWithFixedDelay(this::refresh,0,30,TimeUnit.SECONDS);
    }
    static JSONObject defaults()throws Exception {
        return new JSONObject("{\"schema\":2,\"name\":\"STROKA\",\"style\":\"news\",\"edge\":\"bottom\",\"height\":64,\"clock\":true,\"date\":true,\"rounded\":true,\"playing\":true,\"reducedMotion\":false,\"language\":\"ru\",\"timeZone\":\"Europe/Moscow\",\"separator\":\"▌▌▌\",\"baseSpeed\":45,\"rows\":[{\"id\":\"first\",\"title\":\"Новости\",\"kind\":\"content\",\"sources\":[],\"messages\":[],\"instruments\":[\"BTC-USD\",\"ETH-USD\"]}]}");
    }
    synchronized int revision(){return version;}
    synchronized JSONObject document()throws Exception{return new JSONObject().put("revision",version).put("profile",new JSONObject(profile.toString())).put("status",status);}
    synchronized void save(JSONObject next)throws Exception {
        ProfileRules.validate(next);JSONObject document=new JSONObject().put("revision",version+1).put("profile",next);FileOutputStream out=null;
        try{out=file.startWrite();out.write(document.toString().getBytes("UTF-8"));file.finishWrite(out);}catch(Exception e){if(out!=null)file.failWrite(out);throw e;}
        profile=new JSONObject(next.toString());version++;worker.execute(this::refresh);
    }
    void refresh(){try{
        JSONObject snapshot; synchronized(this){snapshot=new JSONObject(profile.toString());}
        LinkedHashMap<String,String> urls=new LinkedHashMap<>();JSONArray rows=snapshot.getJSONArray("rows");
        for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(r.getString("kind").equals("content")){JSONArray sources=r.getJSONArray("sources");for(int j=0;j<sources.length();j++){JSONObject s=sources.getJSONObject(j);urls.put(s.getString("url"),s.getString("name"));}}else if(r.getString("kind").equals("markets")){JSONArray symbols=r.getJSONArray("instruments");for(int j=0;j<symbols.length();j++){String s=symbols.getString(j);urls.put("https://api.coinbase.com/v2/prices/"+s+"/spot","Coinbase");}}}
        Set<String> active=urls.keySet();synchronized(this){stories.keySet().retainAll(active);fetched.keySet().retainAll(active);}
        int failures=0;
        for(String url:urls.keySet()){
            long now=System.currentTimeMillis();long age;synchronized(this){age=now-fetched.getOrDefault(url,0L);}long cadence=url.contains("api.coinbase.com")?60000:300000;
            if(age<cadence)continue;
            try{byte[] bytes=fetch(url,0);JSONArray items;
                if(url.contains("api.coinbase.com/"))items=market(bytes,url);
                else if(url.startsWith("https://t.me/s/"))items=telegram(new String(bytes,"UTF-8"),urls.get(url));
                else items=feed(bytes,urls.get(url));
                synchronized(this){stories.put(url,items);fetched.put(url,now);}
            }catch(Exception e){failures++;synchronized(this){fetched.put(url,now-cadence+30000);}}
        }
        synchronized(this){status=urls.isEmpty()?"Добавьте источники или свой текст":failures>0?"Часть источников недоступна. Просроченные новости скрываются.":"Телевизор загружает ленту самостоятельно";}
    }catch(Exception e){synchronized(this){status="Проверьте настройки ленты";}}}
    synchronized JSONObject render()throws Exception {
        JSONObject state=new JSONObject(profile.toString());state.put("schema",1).put("serverTime",System.currentTimeMillis()/1000.0).put("brand",profile.getString("name"));
        JSONArray result=new JSONArray(),rows=profile.getJSONArray("rows");double now=System.currentTimeMillis()/1000.0;
        for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i),target=new JSONObject();JSONArray items=new JSONArray();String kind=row.getString("kind");
            if(kind.equals("message")||kind.equals("offline")){JSONArray messages=row.getJSONArray("messages");for(int j=0;j<messages.length();j++)items.put(new JSONObject().put("id",row.getString("id")+"-"+j).put("text",messages.getString(j)).put("expiresAt",JSONObject.NULL));}
            else {ArrayList<JSONObject> all=new ArrayList<>();ArrayList<String> urls=new ArrayList<>();
                if(kind.equals("markets")){JSONArray symbols=row.getJSONArray("instruments");for(int j=0;j<symbols.length();j++)urls.add("https://api.coinbase.com/v2/prices/"+symbols.getString(j)+"/spot");}
                else {JSONArray sources=row.getJSONArray("sources");for(int j=0;j<sources.length();j++)urls.add(sources.getJSONObject(j).getString("url"));}
                Set<String> seen=new HashSet<>();for(String url:urls){JSONArray cached=stories.get(url);if(cached==null)continue;for(int j=0;j<cached.length();j++){JSONObject item=cached.getJSONObject(j);if(item.optDouble("expiresAt",0)>now&&seen.add(item.getString("id")))all.add(item);}}
                all.sort((a,b)->Double.compare(b.optDouble("published",0),a.optDouble("published",0)));for(int j=0;j<Math.min(40,all.size());j++)items.put(all.get(j));
            }
            target.put("title",row.getString("title")).put("kind",kind.equals("markets")?"markets":"content").put("speed",profile.getDouble("baseSpeed")*(1+i*0.15)).put("items",items);result.put(target);
        }
        return state.put("rows",result);
    }
    static byte[] fetch(String raw,int redirects)throws Exception {
        if(redirects>3)throw new IOException("Too many redirects");URL url=ProfileRules.publicURL(raw);
        // Reject feeds resolving to a LAN/loopback/link-local/metadata address before any request.
        InetAddress[] addresses=InetAddress.getAllByName(url.getHost());if(addresses.length==0)throw new IOException();for(InetAddress a:addresses)if(!PublicTLS.isPublic(a))throw new IOException("Non-public feed address");
        HttpsURLConnection c=(HttpsURLConnection)url.openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(4500);c.setReadTimeout(4500);c.setRequestProperty("User-Agent","StrokaTV-Lab/0.3 (+personal RSS reader)");c.setRequestProperty("Accept-Encoding","identity");
        c.setSSLSocketFactory(new PublicTLS(url.getHost(),addresses[0]));
        try{int code=c.getResponseCode();if(code>=300&&code<400){String location=c.getHeaderField("Location");if(location==null)throw new IOException();return fetch(new URL(url,location).toString(),redirects+1);}if(code!=200||c.getContentLength()>1048576)throw new IOException();try(InputStream in=c.getInputStream()){return read(in,1048576);}}finally{c.disconnect();}
    }
    static byte[] read(InputStream in,int max)throws Exception{ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(Thread.currentThread().isInterrupted()||bytes.size()+n>max)throw new IOException();bytes.write(b,0,n);}return bytes.toByteArray();}
    static String clean(String text){return Html.fromHtml(text,Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+"," ").trim();}
    static double date(String value){return FeedParser.date(value);}
    static JSONObject story(String id,String title,String source,double published)throws Exception {
        double now=System.currentTimeMillis()/1000.0;String text=clean(title);
        if(!FeedParser.fresh(published,now)||text.isEmpty()||text.length()>600)return null;
        return new JSONObject().put("id",id).put("text",source+" · "+text).put("published",published).put("expiresAt",published+86400);
    }
    static JSONArray feed(byte[] bytes,String source)throws Exception {
        JSONArray output=new JSONArray();for(FeedParser.Entry e:FeedParser.parse(bytes)){JSONObject item=story(e.id.isEmpty()?source+e.title:e.id,e.title,source,e.published);if(item!=null)output.put(item);}return output;
    }
    static JSONArray telegram(String html,String source)throws Exception {
        JSONArray output=new JSONArray();Pattern boundary=Pattern.compile("data-post=\"([^\"]+)\"");Matcher m=boundary.matcher(html);ArrayList<Integer> at=new ArrayList<>();ArrayList<String> ids=new ArrayList<>();while(m.find()&&at.size()<100){at.add(m.start());ids.add(m.group(1));}at.add(html.length());
        Pattern text=Pattern.compile("<div class=\"tgme_widget_message_text[^\"]*\"[^>]*>(.*?)</div>",Pattern.DOTALL),time=Pattern.compile("<time[^>]*datetime=\"([^\"]+)\"");
        for(int i=0;i<ids.size();i++){String block=html.substring(at.get(i),at.get(i+1));Matcher t=text.matcher(block),d=time.matcher(block);if(t.find()&&d.find()){JSONObject s=story("tg:"+ids.get(i),t.group(1),source,date(d.group(1)));if(s!=null)output.put(s);}}return output;
    }
    static JSONArray market(byte[] bytes,String url)throws Exception {
        JSONObject data=new JSONObject(new String(bytes,"UTF-8")).getJSONObject("data");String amount=data.getString("amount"),currency=data.getString("currency");double now=System.currentTimeMillis()/1000.0;
        double number=Double.parseDouble(amount);if(!Double.isFinite(number)||number<=0)throw new Exception();
        String symbol=url.substring("https://api.coinbase.com/v2/prices/".length()).replace("/spot","");
        return new JSONArray().put(new JSONObject().put("id",symbol).put("text",symbol+"  "+amount+" "+currency+" · Coinbase · запрос "+java.time.LocalTime.now().withNano(0)).put("published",now).put("expiresAt",now+120));
    }
    void close(){worker.shutdownNow();}
}
