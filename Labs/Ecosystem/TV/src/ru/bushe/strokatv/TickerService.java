package ru.bushe.strokatv.lab;

import android.app.*;
import android.os.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.provider.Settings;
import android.graphics.PixelFormat;
import android.view.*;
import android.widget.Toast;
import org.json.JSONObject;
import java.util.concurrent.*;

public final class TickerService extends Service {
    static volatile boolean running=false,connectionReady=false;
    final Handler main=new Handler(Looper.getMainLooper());
    ScheduledExecutorService worker;WindowManager windows;TickerOverlay overlay;
    volatile boolean screenOn=true,ended=false;boolean attached=false;int lastHeight=-1,lastGravity=-1;
    final BroadcastReceiver screen=new BroadcastReceiver(){@Override public void onReceive(Context c,Intent i){screenOn=Intent.ACTION_SCREEN_ON.equals(i.getAction());if(!screenOn)hide();}};
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onCreate(){super.onCreate();
        windows=(WindowManager)getSystemService(WINDOW_SERVICE);overlay=new TickerOverlay(this);
        if(Build.VERSION.SDK_INT>=33)registerReceiver(screen,new IntentFilter(Intent.ACTION_SCREEN_ON){{addAction(Intent.ACTION_SCREEN_OFF);}},Context.RECEIVER_NOT_EXPORTED);else registerReceiver(screen,new IntentFilter(Intent.ACTION_SCREEN_ON){{addAction(Intent.ACTION_SCREEN_OFF);}});
    }
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(intent!=null && "stop".equals(intent.getAction())){stopSelf();return START_NOT_STICKY;}
        if(!Settings.canDrawOverlays(this)){stopSelf();return START_NOT_STICKY;}
        NotificationManager manager=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);manager.createNotificationChannel(new NotificationChannel("ticker",getString(R.string.channel),NotificationManager.IMPORTANCE_LOW));
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,TickerService.class).setAction("stop"),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        PendingIntent open=PendingIntent.getActivity(this,2,new Intent(this,MainActivity.class),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification notification=new Notification.Builder(this,"ticker").setContentTitle(getString(R.string.notice)).setSmallIcon(R.drawable.icon).setContentIntent(open).addAction(new Notification.Action.Builder(null,getString(R.string.stop),stop).build()).setOngoing(true).build();
        try{if(Build.VERSION.SDK_INT>=34)startForeground(1,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else startForeground(1,notification);}catch(Exception e){Toast.makeText(this,R.string.service_failed,Toast.LENGTH_LONG).show();stopSelf();return START_NOT_STICKY;}
        running=true;connectionReady=false;
        if(worker==null){worker=Executors.newSingleThreadScheduledExecutor();worker.scheduleWithFixedDelay(()->{
            if(ended || !screenOn)return;
            
            try{JSONObject data=RuntimeLink.get(this).engine.render();if(data.getInt("schema")!=1 || !Double.isFinite(data.getDouble("serverTime")))throw new Exception();main.post(()->{if(!ended && screenOn)show(data);});}
            catch(Exception e){main.post(()->{if(!ended)hide();});}
        },0,5,TimeUnit.SECONDS);}
        return START_NOT_STICKY;
    }
    void show(JSONObject data){
        try{
            int count=data.getJSONArray("rows").length();if(count<1 || count>4)throw new Exception();
            int height=Math.max(45,Math.min(180,data.optInt("height",80)));
            WindowManager.LayoutParams params=new WindowManager.LayoutParams(-1,Math.round(height*getResources().getDisplayMetrics().density),WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED|WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE|WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,PixelFormat.TRANSLUCENT);
            params.gravity=Gravity.FILL_HORIZONTAL|("top".equals(data.optString("edge"))?Gravity.TOP:Gravity.BOTTOM);params.alpha=0.79f;params.setTitle("Stroka TV ticker");
            overlay.apply(data);
            if(!attached){windows.addView(overlay,params);attached=true;}else if(params.height!=lastHeight || params.gravity!=lastGravity){windows.updateViewLayout(overlay,params);}
            lastHeight=params.height;lastGravity=params.gravity;connectionReady=true;
        }catch(Exception e){hide();Toast.makeText(this,R.string.service_failed,Toast.LENGTH_LONG).show();stopSelf();}
    }
    void hide(){connectionReady=false;lastHeight=-1;lastGravity=-1;overlay.suspend();if(attached){try{windows.removeViewImmediate(overlay);}catch(Exception ignored){}attached=false;}}
    @Override public void onDestroy(){ended=true;running=false;if(worker!=null)worker.shutdownNow();main.removeCallbacksAndMessages(null);hide();try{unregisterReceiver(screen);}catch(Exception ignored){}stopForeground(STOP_FOREGROUND_REMOVE);RuntimeLink.close();super.onDestroy();}
}
