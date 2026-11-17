package ru.bushe.strokatv;
public final class LocalLinkTest {
 public static void main(String[] args)throws Exception {
  int count=0;
  for(String input:new String[]{"192.168.1.5:54321","http://10.1.2.3:8080/","172.16.0.1:9999","172.31.255.1:1024"}){if(!LocalLink.base(input).startsWith("http://"))throw new AssertionError();count++;}
  for(String input:new String[]{"8.8.8.8:8080","127.0.0.1:8080","172.32.0.1:8080","192.168.1.4:80","https://192.168.1.4:8000","192.168.1.4:8000/evil","192.168.1.4:8000?secret=x","user@192.168.1.4:8080","192.168.1.4:8000#x","192.168.1.999:8000","192.168.1.4","localhost:8080","[::1]:8080"}){boolean rejected=false;try{LocalLink.base(input);}catch(Exception e){rejected=true;}if(!rejected)throw new AssertionError("Accepted forbidden address");count++;}
  LocalLink.statePath("/1234567890abcdef1234567890abcdef/state");count++;
  for(String input:new String[]{"/state","/pair","/../control","/1234567890abcdef1234567890abcdef/state?x=1"}){boolean rejected=false;try{LocalLink.statePath(input);}catch(Exception e){rejected=true;}if(!rejected)throw new AssertionError("Accepted invalid capability");count++;}
  System.out.println(count+" Android local connection validation checks passed");
 }
}
