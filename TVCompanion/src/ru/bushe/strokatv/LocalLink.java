package ru.bushe.strokatv;

import java.net.URI;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.*;
import org.json.JSONObject;

final class LocalLink {
    static String base(String input) throws Exception {
        String value = input.trim();if(!value.startsWith("http://"))value="http://"+value;
        URI uri=new URI(value);String host=uri.getHost();
        if(!"http".equals(uri.getScheme()) || host==null || uri.getUserInfo()!=null || uri.getQuery()!=null || uri.getFragment()!=null || !(uri.getPath().isEmpty() || "/".equals(uri.getPath())) || uri.getPort()<1024 || uri.getPort()>65535)throw new IOException("Invalid address");
        String[] parts=host.split("\\.",-1);if(parts.length!=4)throw new IOException("IPv4 required");int[] n=new int[4];
        for(int i=0;i<4;i++){if(!parts[i].matches("[0-9]{1,3}"))throw new IOException("IPv4 required");n[i]=Integer.parseInt(parts[i]);if(n[i]>255)throw new IOException("IPv4 required");}
        if(!(n[0]==10 || (n[0]==172 && n[1]>=16 && n[1]<=31) || (n[0]==192 && n[1]==168)))throw new IOException("Private address required");
        return "http://"+host+":"+uri.getPort();
    }
    static String statePath(String path)throws Exception {if(!path.matches("/[a-f0-9]{32}/state"))throw new IOException("Invalid session");return path;}
    static JSONObject request(String base,String path,JSONObject body)throws Exception {
        base=base(base);if(!"/pair".equals(path))statePath(path);
        HttpURLConnection c=(HttpURLConnection)new URL(base+path).openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(4000);c.setReadTimeout(4000);c.setUseCaches(false);
        try{
            c.setRequestMethod(body==null?"GET":"POST");c.setRequestProperty("Accept","application/json");
            if(body!=null){byte[] data=body.toString().getBytes("UTF-8");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setFixedLengthStreamingMode(data.length);try(OutputStream stream=c.getOutputStream()){stream.write(data);}}
            if(c.getResponseCode()!=200)throw new IOException("Request refused");
            if(c.getContentLengthLong()>512000)throw new IOException("Oversized response");
            ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] chunk=new byte[4096];int read;while((read=in.read(chunk))!=-1){if(out.size()+read>512000)throw new IOException("Oversized response");out.write(chunk,0,read);}}
            return new JSONObject(out.toString("UTF-8"));
        }finally{c.disconnect();}
    }
}
