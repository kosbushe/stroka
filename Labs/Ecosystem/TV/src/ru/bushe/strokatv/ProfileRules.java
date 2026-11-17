package ru.bushe.strokatv.lab;
import org.json.*;
import java.net.*;
import java.util.*;

final class ProfileRules {
    static JSONObject validate(JSONObject p)throws Exception {
        for(String key:new String[]{"clock","date","rounded","playing","reducedMotion"})if(!(p.get(key) instanceof Boolean))throw new Exception("Boolean required");
        for(String key:new String[]{"schema","height","baseSpeed"})if(!(p.get(key) instanceof Number))throw new Exception("Number required");
        if(p.getDouble("schema")!=p.getInt("schema")||p.getDouble("height")!=p.getInt("height"))throw new Exception("Integer required");
        if(p.getInt("schema")!=2 || p.getString("name").trim().isEmpty() || p.getString("name").length()>96
            || !Arrays.asList("news","night","minimal","glass").contains(p.getString("style"))
            || !Arrays.asList("top","bottom").contains(p.getString("edge"))
            || !Arrays.asList("ru","en").contains(p.getString("language"))
            || !Arrays.asList(TimeZone.getAvailableIDs()).contains(p.getString("timeZone"))
            || p.getInt("height")<45 || p.getInt("height")>180 || p.getString("separator").length()>24
            || !Double.isFinite(p.getDouble("baseSpeed")) || p.getDouble("baseSpeed")<10 || p.getDouble("baseSpeed")>120)throw new Exception("Invalid profile");
        JSONArray rows=p.getJSONArray("rows");if(rows.length()<1||rows.length()>4)throw new Exception("Invalid rows");Set<String> ids=new HashSet<>();
        for(int i=0;i<rows.length();i++){
            JSONObject r=rows.getJSONObject(i);String id=r.getString("id");
            if(id.isEmpty()||id.length()>64||!ids.add(id)||r.getString("title").length()>96||!Arrays.asList("content","message","markets","offline").contains(r.getString("kind")))throw new Exception("Invalid row");
            JSONArray sources=r.getJSONArray("sources"),messages=r.getJSONArray("messages"),symbols=r.getJSONArray("instruments");
            if(sources.length()>24||messages.length()>40||symbols.length()>24)throw new Exception("Too many items");
            for(int j=0;j<sources.length();j++){JSONObject s=sources.getJSONObject(j);publicURL(s.getString("url"));if(s.getString("name").length()>160||s.getString("id").length()>128||s.getString("language").length()>8||s.getString("category").length()>64)throw new Exception("Invalid source");}
            for(int j=0;j<messages.length();j++)if(messages.getString(j).length()>1200)throw new Exception("Message too long");
            for(int j=0;j<symbols.length();j++)if(!symbols.getString(j).matches("[A-Z0-9-]{2,16}"))throw new Exception("Invalid market symbol");
        }
        return p;
    }
    static URL publicURL(String raw)throws Exception {
        if(raw.length()>2048)throw new Exception("URL too long");URL u=new URL(raw);
        String h=u.getHost().toLowerCase(Locale.ROOT);
        if(!"https".equals(u.getProtocol())||u.getUserInfo()!=null||u.getRef()!=null||(u.getPort()!=-1&&u.getPort()!=443)
            || !h.contains(".")||!h.matches("[a-z0-9.-]+")||h.matches("[0-9.]+")||h.endsWith(".local")||h.endsWith(".internal")||h.endsWith(".localhost"))throw new Exception("Public HTTPS feed required");
        return u;
    }
    static boolean privatePeer(InetAddress a){byte[] x=a.getAddress();return x.length==4 && ((x[0]&255)==10 || ((x[0]&255)==172&&(x[1]&255)>=16&&(x[1]&255)<=31) || ((x[0]&255)==192&&(x[1]&255)==168));}
}
