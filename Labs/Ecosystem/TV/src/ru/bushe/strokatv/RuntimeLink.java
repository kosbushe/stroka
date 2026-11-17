package ru.bushe.strokatv.lab;
import android.content.Context;
final class RuntimeLink {
    static RuntimeLink instance;
    final Engine engine;final LinkServer server;
    private RuntimeLink(Context c)throws Exception{engine=new Engine(c);server=new LinkServer(c,engine);}
    static synchronized RuntimeLink get(Context c)throws Exception{if(instance==null)instance=new RuntimeLink(c);return instance;}
    static synchronized void close(){if(instance!=null){instance.server.close();instance.engine.close();instance=null;}}
}
