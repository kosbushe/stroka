package ru.bushe.strokatv.lab;
import org.xml.sax.*;
import org.xml.sax.helpers.DefaultHandler;
import javax.xml.parsers.*;
import java.io.*;
import java.util.*;
import java.time.*;
import java.time.format.*;

final class FeedParser {
    static final class Entry {final String id,title;final double published;Entry(String i,String t,double p){id=i;title=t;published=p;}}
    static double date(String value){try{return Instant.parse(value.trim()).getEpochSecond();}catch(Exception ignored){}try{return OffsetDateTime.parse(value.trim()).toEpochSecond();}catch(Exception ignored){}try{return ZonedDateTime.parse(value.trim(),DateTimeFormatter.RFC_1123_DATE_TIME).toEpochSecond();}catch(Exception ignored){}return 0;}
    static boolean fresh(double published,double now){return Double.isFinite(published)&&published>0&&published<=now&&published+86400>now;}
    static List<Entry> parse(byte[] bytes)throws Exception {
        if(bytes.length>1048576)throw new IOException("Feed limit");
        String probe=new String(bytes,java.nio.charset.StandardCharsets.ISO_8859_1).toLowerCase(Locale.ROOT).replace("\u0000", "");
        if(probe.indexOf("<!doctype")>=0||probe.indexOf("<!entity")>=0)throw new IOException("DTD is not supported");
        List<Entry> output=new ArrayList<>();SAXParserFactory f=SAXParserFactory.newInstance();f.setNamespaceAware(true);
        try{f.setFeature("http://xml.org/sax/features/external-general-entities",false);}catch(Exception ignored){}
        try{f.setFeature("http://xml.org/sax/features/external-parameter-entities",false);}catch(Exception ignored){}
        XMLReader parser=f.newSAXParser().getXMLReader();parser.setEntityResolver((publicId,systemId)->{throw new SAXException("External entity denied");});
        parser.setContentHandler(new DefaultHandler(){int depth,itemDepth=-1,fieldDepth=-1,entries;String field="",title="",published="",id="";StringBuilder buffer=new StringBuilder();
            public void startElement(String uri,String local,String q,Attributes a)throws SAXException{
                depth++;String n=local.isEmpty()?q:local;
                if(itemDepth<0&&(n.equals("item")||n.equals("entry"))){itemDepth=depth;title="";published="";id="";if(++entries>200)throw new SAXException("Item limit");}
                else if(itemDepth>=0&&depth==itemDepth+1){field=n;fieldDepth=depth;buffer.setLength(0);if(n.equals("link")&&a.getValue("href")!=null&&("alternate".equals(a.getValue("rel"))||a.getValue("rel")==null))id=a.getValue("href");}
            }
            public void characters(char[] ch,int start,int length)throws SAXException{if(fieldDepth>=0){if(buffer.length()+length>16384)throw new SAXException("Field limit");buffer.append(ch,start,length);}}
            public void endElement(String uri,String local,String q)throws SAXException{
                if(depth==fieldDepth){String value=buffer.toString().trim();
                    if(field.equals("title"))title=value;
                    else if(field.equals("pubDate")||field.equals("published")||field.equals("date"))published=value;
                    else if((field.equals("guid")||field.equals("id")||field.equals("link"))&&!value.isEmpty())id=value;
                    fieldDepth=-1;buffer.setLength(0);
                }
                if(depth==itemDepth){output.add(new Entry(id,title,date(published)));itemDepth=-1;fieldDepth=-1;}depth--;
            }
        });parser.parse(new InputSource(new ByteArrayInputStream(bytes)));return output;
    }
}
