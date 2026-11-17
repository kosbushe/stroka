package ru.bushe.strokatv.lab;
import java.net.*;
import java.io.*;
import javax.net.ssl.*;

// Connect to the vetted DNS answer, then retain the real hostname for TLS/SNI checks.
// A DNS rebinding between a preflight lookup and URLConnection's lookup cannot reach the LAN.
final class PublicTLS extends SSLSocketFactory {
    final SSLSocketFactory system=(SSLSocketFactory)SSLSocketFactory.getDefault();
    final InetAddress address;final String host;
    PublicTLS(String host,InetAddress address){this.host=host;this.address=address;}
    public String[] getDefaultCipherSuites(){return system.getDefaultCipherSuites();}
    public String[] getSupportedCipherSuites(){return system.getSupportedCipherSuites();}
    java.net.Socket connect(String name,int port)throws IOException{
        if(!host.equalsIgnoreCase(name)||port!=443)throw new IOException("Unexpected feed endpoint");
        Socket raw=new Socket();try{raw.connect(new InetSocketAddress(address,port),4500);raw.setSoTimeout(4500);return system.createSocket(raw,host,port,true);}catch(IOException e){raw.close();throw e;}
    }
    public Socket createSocket(String h,int p)throws IOException{return connect(h,p);}
    public Socket createSocket(String h,int p,InetAddress local,int localPort)throws IOException{return connect(h,p);}
    public Socket createSocket(InetAddress h,int p)throws IOException{return connect(host,p);}
    public Socket createSocket(InetAddress h,int p,InetAddress local,int localPort)throws IOException{return connect(host,p);}
    public Socket createSocket(Socket existing,String h,int p,boolean close)throws IOException{
        // URLConnection may supply a preconnected socket. Never use its unvetted destination.
        if(close)existing.close();return connect(h,p);
    }
    static boolean isPublic(InetAddress a){
        if(a.isAnyLocalAddress()||a.isLoopbackAddress()||a.isLinkLocalAddress()||a.isSiteLocalAddress()||a.isMulticastAddress())return false;
        byte[] b=a.getAddress();if(b.length==16)return (b[0]&254)!=252;
        int x=b[0]&255,y=b[1]&255,z=b[2]&255;
        return x!=0&&x!=127&&x<224&&!(x==100&&y>=64&&y<=127)&&!(x==198&&(y==18||y==19))&&!(x==192&&y==0)&&!(x==198&&y==51&&z==100)&&!(x==203&&y==0&&z==113);
    }
}
