package ru.bushe.strokatv;

import android.app.*;
import android.os.*;
import android.content.*;
import android.net.Uri;
import android.provider.Settings;
import android.graphics.Color;
import android.view.*;
import android.widget.*;
import android.text.InputType;
import android.Manifest;
import org.json.JSONObject;
import java.util.concurrent.*;

public final class MainActivity extends Activity {
    EditText address,code;TextView status;Button pair;
    final Handler statusTimer=new Handler(Looper.getMainLooper());
    final Runnable statusRefresh=new Runnable(){public void run(){if(status!=null && TickerService.running)status.setText(TickerService.connectionReady?R.string.running:R.string.waiting_connection);statusTimer.postDelayed(this,1000);}};
    final ExecutorService worker=Executors.newSingleThreadExecutor();
    int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    TextView text(LinearLayout box,String value,int size){TextView t=new TextView(this);t.setText(value);t.setTextColor(Color.WHITE);t.setTextSize(size);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(12);box.addView(t,p);return t;}
    Button button(LinearLayout box,int title,Runnable action){Button b=new Button(this);b.setText(title);b.setAllCaps(false);b.setTextSize(17);b.setMinHeight(dp(48));b.setOnClickListener(v->action.run());box.addView(b,new LinearLayout.LayoutParams(-1,-2));return b;}
    @Override public void onCreate(Bundle state){super.onCreate(state);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setBackgroundColor(Color.rgb(17,24,34));
        LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(dp(42),dp(26),dp(42),dp(26));scroll.addView(box);setContentView(scroll);
        text(box,"Stroka TV",30);text(box,getString(R.string.intro),19);text(box,getString(R.string.instructions),15);
        address=new EditText(this);address.setSingleLine(true);address.setTextColor(Color.WHITE);address.setHintTextColor(Color.LTGRAY);address.setTextSize(18);address.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_URI);address.setHint(R.string.address);address.setText(getPreferences(0).getString("address",""));box.addView(address,new LinearLayout.LayoutParams(-1,dp(54)));
        code=new EditText(this);code.setSingleLine(true);code.setTextColor(Color.WHITE);code.setHintTextColor(Color.LTGRAY);code.setTextSize(18);code.setInputType(InputType.TYPE_CLASS_NUMBER);code.setHint(R.string.code);code.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(6)});box.addView(code,new LinearLayout.LayoutParams(-1,dp(54)));
        pair=button(box,R.string.pair,this::pair);
        button(box,R.string.permission,()->{try{startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:"+getPackageName())));}catch(ActivityNotFoundException e){try{startActivity(new Intent(Settings.ACTION_SETTINGS));}catch(Exception ignored){}Toast.makeText(this,R.string.no_settings,Toast.LENGTH_LONG).show();}});
        LinearLayout actions=new LinearLayout(this);actions.setOrientation(LinearLayout.HORIZONTAL);box.addView(actions);
        Button start=new Button(this);start.setText(R.string.start);start.setAllCaps(false);start.setTextSize(18);actions.addView(start,new LinearLayout.LayoutParams(0,dp(54),1));start.setOnClickListener(v->startTicker());
        Button stop=new Button(this);stop.setText(R.string.stop);stop.setAllCaps(false);stop.setTextSize(18);actions.addView(stop,new LinearLayout.LayoutParams(0,dp(54),1));stop.setOnClickListener(v->{stopService(new Intent(this,TickerService.class));status.setText(R.string.stopped);});
        status=text(box,"",15);text(box,getString(R.string.privacy),13);address.requestFocus();
    }
    @Override protected void onResume(){super.onResume();if(status!=null)status.setText(TickerService.running?(TickerService.connectionReady?R.string.running:R.string.waiting_connection):getSharedPreferences("link",0).contains("path")?R.string.paired:R.string.not_paired);statusTimer.postDelayed(statusRefresh,1000);}
    @Override protected void onPause(){statusTimer.removeCallbacks(statusRefresh);super.onPause();}
    void pair(){final String host,pin=code.getText().toString();try{host=LocalLink.base(address.getText().toString());}catch(Exception e){status.setText(R.string.invalid_address);return;}if(!pin.matches("[0-9]{6}")){status.setText(R.string.invalid_code);return;}
        pair.setEnabled(false);status.setText(R.string.connecting);
        worker.execute(()->{try{JSONObject body=new JSONObject();body.put("code",pin);JSONObject result=LocalLink.request(host,"/pair",body);String path=LocalLink.statePath(result.getString("statePath"));if(isFinishing() || isDestroyed() || Thread.currentThread().isInterrupted())return;getSharedPreferences("link",0).edit().putString("base",host).putString("path",path).apply();getPreferences(0).edit().putString("address",host).apply();runOnUiThread(()->{if(isFinishing() || isDestroyed())return;stopService(new Intent(this,TickerService.class));code.setText("");status.setText(R.string.paired);pair.setEnabled(true);});}catch(Exception e){runOnUiThread(()->{if(!isFinishing()){status.setText(R.string.connect_error);pair.setEnabled(true);}});}});
    }
    void startTicker(){if(!Settings.canDrawOverlays(this)){status.setText(R.string.needs_overlay);return;}if(!getSharedPreferences("link",0).contains("path")){status.setText(R.string.not_paired);return;}
        if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},7);
        try{startForegroundService(new Intent(this,TickerService.class));status.setText(R.string.waiting_connection);}catch(Exception e){status.setText(R.string.service_failed);}
    }
    @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
