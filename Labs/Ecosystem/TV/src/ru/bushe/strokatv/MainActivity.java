package ru.bushe.strokatv.lab;

import android.app.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import android.net.Uri;
import android.graphics.*;
import android.view.*;
import android.widget.*;
import com.google.zxing.*;
import com.google.zxing.common.BitMatrix;
import java.net.*;
import java.util.*;

public final class MainActivity extends Activity {
    RuntimeLink runtime;ImageView qr;TextView status,hint;String ticket="";long refreshAt;
    final Handler timer=new Handler(Looper.getMainLooper());
    final Runnable pulse=new Runnable(){public void run(){if(runtime!=null){status.setText(TickerService.running?"Лента работает. Телефон можно заблокировать.":"Подключите iPhone или Mac, чтобы выбрать ленту.");if(SystemClock.elapsedRealtime()>refreshAt && (runtime.server.pending==null||runtime.server.pending.denied))newQR();}timer.postDelayed(this,1000);}};
    int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    TextView text(LinearLayout box,String value,int size){TextView t=new TextView(this);t.setText(value);t.setTextColor(Color.WHITE);t.setTextSize(size);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(14);box.addView(t,p);return t;}
    Button button(LinearLayout box,String value,Runnable action){Button b=new Button(this);b.setText(value);b.setAllCaps(false);b.setTextSize(16);b.setOnClickListener(v->action.run());box.addView(b,new LinearLayout.LayoutParams(-1,dp(52)));return b;}
    @Override public void onCreate(Bundle saved){super.onCreate(saved);
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(dp(48),dp(24),dp(48),dp(24));root.setBackgroundColor(Color.rgb(16,22,31));setContentView(root);
        text(root,"Stroka TV  /  Lab",18);text(root,"Ваша лента. На большом экране.",32);
        LinearLayout columns=new LinearLayout(this);root.addView(columns,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout info=new LinearLayout(this);info.setOrientation(LinearLayout.VERTICAL);info.setPadding(0,dp(12),dp(38),0);columns.addView(info,new LinearLayout.LayoutParams(0,-1,1));
        text(info,"1  Откройте Stroka на iPhone\n    и отсканируйте QR.",23);
        text(info,"2  Подтвердите подключение\n    здесь, на телевизоре.",23);
        status=text(info,"",15);
        button(info,"Разрешить строку поверх приложений",()->startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:"+getPackageName()))));
        button(info,"Показать новый QR",this::newQR);
        button(info,"Отключить все устройства и остановить",()->{if(runtime!=null)runtime.server.revokeAll();stopService(new Intent(this,TickerService.class));RuntimeLink.close();runtime=null;ticket="";qr.setImageDrawable(null);hint.setText("Устройства отключены. Для нового подключения нажмите «Показать новый QR».");});
        LinearLayout code=new LinearLayout(this);code.setGravity(Gravity.CENTER);code.setOrientation(LinearLayout.VERTICAL);columns.addView(code,new LinearLayout.LayoutParams(dp(300),-1));
        qr=new ImageView(this);qr.setScaleType(ImageView.ScaleType.FIT_CENTER);code.addView(qr,new LinearLayout.LayoutParams(dp(236),dp(236)));
        hint=text(code,"",13);hint.setGravity(Gravity.CENTER);
        text(root,"Оба устройства должны быть в одной домашней сети Wi-Fi. Регистрация не нужна.",13);
    }
    @Override protected void onResume(){super.onResume();try{runtime=RuntimeLink.get(this);runtime.server.approval=this::confirm;if(Settings.canDrawOverlays(this))newQR();else hint.setText("Сначала разрешите показ поверх приложений кнопкой слева.");}catch(Exception e){hint.setText("Не удалось включить подключение. Перезапустите приложение.");}timer.post(pulse);}
    @Override protected void onPause(){timer.removeCallbacksAndMessages(null);if(runtime!=null)runtime.server.approval=null;super.onPause();}
    void newQR(){try{
        if(!Settings.canDrawOverlays(this)){hint.setText("Сначала разрешите показ поверх приложений.");refreshAt=Long.MAX_VALUE;return;}
        runtime=RuntimeLink.get(this);runtime.server.approval=this::confirm;
        String ip=localIP();if(ip==null){hint.setText("Подключите телевизор к домашней сети Wi-Fi.");refreshAt=SystemClock.elapsedRealtime()+10000;return;}
        ticket=runtime.server.ticket(ip);Map<EncodeHintType,Object> hints=new EnumMap<>(EncodeHintType.class);hints.put(EncodeHintType.MARGIN,4);hints.put(EncodeHintType.ERROR_CORRECTION,com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M);
        BitMatrix bits=new com.google.zxing.qrcode.QRCodeWriter().encode(ticket,BarcodeFormat.QR_CODE,720,720,hints);Bitmap bitmap=Bitmap.createBitmap(720,720,Bitmap.Config.RGB_565);int[] pixels=new int[720*720];for(int y=0;y<720;y++)for(int x=0;x<720;x++)pixels[y*720+x]=bits.get(x,y)?Color.BLACK:Color.WHITE;bitmap.setPixels(pixels,0,720,0,0,720,720);qr.setImageBitmap(bitmap);
        refreshAt=SystemClock.elapsedRealtime()+120000;hint.setText("QR действует 2 минуты\nStroka TV · "+runtime.server.identity.id.substring(0,6));
    }catch(Exception e){hint.setText("Не удалось создать QR. Проверьте сеть и повторите.");}}
    void confirm(String name,String challenge,Runnable approve,Runnable deny){
        if(isFinishing()||!Settings.canDrawOverlays(this)){deny.run();return;}
        new AlertDialog.Builder(this).setTitle("Подключить «"+name+"»?")
            .setMessage("Сверьте число на телефоне или Mac:\n\n"+challenge+"\n\nУстройство сможет менять вашу ленту и управлять её показом.")
            .setPositiveButton("Разрешить и запустить",(d,w)->{approve.run();hint.setText("Подключено. Для второго устройства нажмите «Показать новый QR».");refreshAt=Long.MAX_VALUE;})
            .setNegativeButton("Отклонить",(d,w)->{deny.run();newQR();}).setOnCancelListener(d->{deny.run();newQR();}).show();
    }
    static String localIP(){try{ArrayList<String> ips=new ArrayList<>();for(Enumeration<NetworkInterface> it=NetworkInterface.getNetworkInterfaces();it.hasMoreElements();){NetworkInterface n=it.nextElement();if(!n.isUp()||n.isLoopback())continue;for(Enumeration<InetAddress> a=n.getInetAddresses();a.hasMoreElements();){InetAddress ip=a.nextElement();if(ProfileRules.privatePeer(ip)){if(n.getName().startsWith("wlan"))return ip.getHostAddress();ips.add(ip.getHostAddress());}}}return ips.isEmpty()?null:ips.get(0);}catch(Exception e){return null;}}
}
