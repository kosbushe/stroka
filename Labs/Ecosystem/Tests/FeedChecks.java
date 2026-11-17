package ru.bushe.strokatv.lab;
import java.nio.charset.StandardCharsets;
import java.net.*;
import java.util.*;
public final class FeedChecks {
    static int count;
    static void check(boolean v,String message){if(!v)throw new AssertionError(message);count++;}
    static List<FeedParser.Entry> parse(String s)throws Exception{return FeedParser.parse(s.getBytes(StandardCharsets.UTF_8));}
    public static void main(String[] args)throws Exception {
        double now=1800000000;
        check(FeedParser.fresh(now-86399,now),"24h lower boundary");check(!FeedParser.fresh(now-86400,now),"24h expired");check(!FeedParser.fresh(now+1,now),"Future denied");check(!FeedParser.fresh(0,now),"Unknown date denied");check(!FeedParser.fresh(Double.NaN,now),"NaN denied");
        String date="2027-01-15T07:59:00Z";
        List<FeedParser.Entry> rss=parse("<rss><channel><item><title>A &amp; B</title><guid>one</guid><pubDate>Fri, 15 Jan 2027 07:59:00 GMT</pubDate></item></channel></rss>");
        check(rss.size()==1&&rss.get(0).title.equals("A & B"),"RSS title");check(rss.get(0).published==FeedParser.date(date),"RSS date");
        List<FeedParser.Entry> atom=parse("<feed xmlns='http://www.w3.org/2005/Atom'><entry><title type='xhtml'><div xmlns='http://www.w3.org/1999/xhtml'>Nested <b>headline</b></div></title><published>"+date+"</published><updated>2099-01-01T00:00:00Z</updated><link href='https://example.com/one'/></entry></feed>");
        check(atom.size()==1&&atom.get(0).title.equals("Nested headline"),"Nested Atom title preserved");check(atom.get(0).published==FeedParser.date(date),"Updated never replaces published");
        check(parse("<feed><entry><title>A</title><updated>"+date+"</updated></entry></feed>").get(0).published==0,"Updated-only has no original publication");
        boolean rejected=false;try{parse("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss><item><title>&x;</title></item></rss>");}catch(Exception e){rejected=true;}check(rejected,"XXE rejected");
        rejected=false;try{FeedParser.parse("<!DOCTYPE rss [<!ENTITY x 'expanded'>]><rss><item><title>&x;</title></item></rss>".getBytes("UTF-16"));}catch(Exception e){rejected=true;}check(rejected,"UTF-16 DTD rejected");
        StringBuilder many=new StringBuilder("<rss>");for(int i=0;i<201;i++)many.append("<item><title>a</title></item>");many.append("</rss>");rejected=false;try{parse(many.toString());}catch(Exception e){rejected=true;}check(rejected,"Item bound");
        for(String ip:new String[]{"127.0.0.1","10.0.0.1","172.16.0.1","192.168.0.1","169.254.169.254","100.100.100.200","198.18.0.1","0.0.0.0","224.0.0.1","::1","fd00::1","fe80::1"})check(!PublicTLS.isPublic(InetAddress.getByName(ip)),"Non-public destination denied");
        for(String ip:new String[]{"8.8.8.8","1.1.1.1","2606:4700:4700::1111"})check(PublicTLS.isPublic(InetAddress.getByName(ip)),"Public destination allowed");
        System.out.println("PASS "+count+" publication, RSS, Atom, XXE and destination checks");
    }
}
