package ru.bushe.strokatv.lab;

import android.content.Context;
import android.os.*;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;
import android.util.*;
import android.text.*;
import android.text.style.ForegroundColorSpan;
import org.json.*;
import java.util.*;
import java.text.SimpleDateFormat;

// Text is shaped only when content changes and rasterized into bounded 512px tiles.
// A single vsync clock advances all lanes; each frame draws only the visible bitmaps.
final class TickerOverlay extends LinearLayout implements Choreographer.FrameCallback {
    static final int TILE=512;
    final TextView brand,clock;
    final LinearLayout centre;
    final Handler timer=new Handler(Looper.getMainLooper());
    final ArrayList<Lane> lanes=new ArrayList<>();
    final Choreographer choreographer=Choreographer.getInstance();
    final Runnable pulse=()->tick();
    JSONObject data;
    long anchor,lastFrame;
    double serverTime;
    boolean clockOn,frames;
    String look="news",chromeKey="",clockKey="";

    TickerOverlay(Context c){super(c);setOrientation(HORIZONTAL);setClipChildren(true);
        brand=new TextView(c);brand.setGravity(Gravity.CENTER);brand.setMaxLines(2);brand.setPadding(dp(4),0,dp(4),0);brand.setTypeface(Typeface.create("sans-serif-medium",0));brand.setAutoSizeTextTypeUniformWithConfiguration(8,18,1,TypedValue.COMPLEX_UNIT_SP);addView(brand,new LayoutParams(dp(92),-1));
        centre=new LinearLayout(c);centre.setOrientation(VERTICAL);centre.setClipChildren(true);addView(centre,new LayoutParams(0,-1,1));
        clock=new TextView(c);clock.setGravity(Gravity.CENTER);clock.setTypeface(Typeface.create("sans-serif-medium",0));clock.setFontFeatureSettings("tnum");addView(clock,new LayoutParams(dp(100),-1));
    }
    int dp(float n){return Math.round(n*getResources().getDisplayMetrics().density);}
    double now(){return serverTime+(SystemClock.elapsedRealtime()-anchor)/1000.0;}
    void apply(JSONObject model)throws Exception {
        data=model;serverTime=model.getDouble("serverTime");anchor=SystemClock.elapsedRealtime();look=model.optString("style","news");
        boolean light="news".equals(look)||"minimal".equals(look);
        int bg=Color.parseColor(light?"#F5F6F8":"#111820"),ink=light?Color.rgb(23,27,32):Color.WHITE;
        String nextChrome=look+model.optBoolean("rounded",true)+model.optString("brand","STROKA")+model.optBoolean("clock",true);
        if(!chromeKey.equals(nextChrome)){
            chromeKey=nextChrome;
            GradientDrawable background=new GradientDrawable();background.setColor(bg);background.setCornerRadius(model.optBoolean("rounded",true)?dp(12):0);setBackground(background);setClipToOutline(true);
            brand.setText(model.optString("brand","STROKA"));brand.setTextColor("minimal".equals(look)?ink:Color.WHITE);brand.setBackgroundColor(Color.parseColor("news".equals(look)?"#C9162D":"minimal".equals(look)?"#F5F6F8":"#263140"));
            clockOn=model.optBoolean("clock",true);clock.setVisibility(clockOn?VISIBLE:GONE);clock.setTextColor(Color.WHITE);clock.setBackgroundColor(Color.rgb(32,37,45));clockKey="";
        }
        JSONArray rows=model.getJSONArray("rows");
        if(lanes.size()!=rows.length()){
            lanes.clear();centre.removeAllViews();
            for(int i=0;i<rows.length();i++){Lane lane=new Lane(getContext());lanes.add(lane);centre.addView(lane,new LayoutParams(-1,0,1));}
        }
        for(int i=0;i<lanes.size();i++){
            JSONObject row=rows.getJSONObject(i);Lane lane=lanes.get(i);float weight="markets".equals(row.optString("kind"))?0.85f:1;
            LayoutParams params=(LayoutParams)lane.getLayoutParams();if(params.weight!=weight){params.weight=weight;lane.setLayoutParams(params);}
            lane.set(row,model.optBoolean("playing",true),model.optBoolean("reducedMotion",false),model.optString("separator","///"),ink);
        }
        tick();updateFrames();
    }
    void tick(){timer.removeCallbacks(pulse);if(data==null || !isAttachedToWindow())return;
        if(clockOn){
            Locale locale="ru".equals(data.optString("language"))?new Locale("ru"):Locale.ENGLISH;
            TimeZone zone=TimeZone.getTimeZone(data.optString("timeZone",TimeZone.getDefault().getID()));
            SimpleDateFormat time=new SimpleDateFormat("HH:mm",locale),date=new SimpleDateFormat("EEE, d MMM",locale);time.setTimeZone(zone);date.setTimeZone(zone);
            Date instant=new Date((long)(now()*1000));String main=time.format(instant),sub=data.optBoolean("date",true)?date.format(instant):"";
            String key=main+"|"+sub;
            if(!clockKey.equals(key)){clockKey=key;SpannableStringBuilder value=new SpannableStringBuilder(main);value.setSpan(new android.text.style.AbsoluteSizeSpan(26,true),0,value.length(),33);
                if(!sub.isEmpty()){int start=value.length();value.append("\n").append(sub);value.setSpan(new android.text.style.AbsoluteSizeSpan(9,true),start,value.length(),33);}clock.setText(value);}
        }
        for(int i=0;i<lanes.size();i++)lanes.get(i).expire();
        timer.postDelayed(pulse,1000);updateFrames();
    }
    boolean moving(){if(!isAttachedToWindow() || getWindowVisibility()!=VISIBLE)return false;for(int i=0;i<lanes.size();i++)if(lanes.get(i).moving())return true;return false;}
    void updateFrames(){boolean wanted=moving();if(wanted && !frames){frames=true;lastFrame=0;choreographer.postFrameCallback(this);}else if(!wanted && frames){frames=false;lastFrame=0;choreographer.removeFrameCallback(this);}}
    @Override public void doFrame(long nanos){
        if(!frames || !moving()){frames=false;lastFrame=0;return;}
        double seconds=lastFrame==0?0:Math.max(0,(nanos-lastFrame)/1_000_000_000.0);lastFrame=nanos;
        for(int i=0;i<lanes.size();i++){Lane lane=lanes.get(i);if(lane.moving()){lane.advance(seconds);lane.invalidate();}}
        choreographer.postFrameCallback(this);
    }
    void suspend(){timer.removeCallbacksAndMessages(null);choreographer.removeFrameCallback(this);frames=false;lastFrame=0;}
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();tick();updateFrames();}
    @Override protected void onDetachedFromWindow(){suspend();super.onDetachedFromWindow();}
    @Override protected void onWindowVisibilityChanged(int visibility){super.onWindowVisibilityChanged(visibility);if(lanes!=null){if(visibility==VISIBLE){tick();updateFrames();}else suspend();}}

    static final class Segment {
        final String id;final StaticLayout layout;final int width;final double start;
        Segment(String id,StaticLayout layout,int width,double start){this.id=id;this.layout=layout;this.width=width;this.start=start;}
    }
    final class Lane extends View {
        final TextPaint textPaint=new TextPaint(Paint.ANTI_ALIAS_FLAG|Paint.SUBPIXEL_TEXT_FLAG);
        final Paint bitmapPaint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        final ArrayList<Segment> segments=new ArrayList<>();
        final LruCache<Long,Bitmap> tiles=new LruCache<>(8);
        JSONObject row;
        StaticLayout staticText;
        String fingerprint="",separator="///";
        boolean playing,reduced;
        int ink,phraseIndex,backgroundColor=Color.TRANSPARENT;
        float speed=95,fontPixels;
        double position,total;
        long lastPhrase;
        Lane(Context c){super(c);setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);textPaint.setTypeface(Typeface.create("sans-serif-medium",0));}
        boolean moving(){return playing && !reduced && total>0 && getWidth()>0 && getHeight()>0;}
        void set(JSONObject next,boolean play,boolean reduce,String marker,int normalInk){
            boolean changed=playing!=play || reduced!=reduce;row=next;playing=play;reduced=reduce;separator=marker;
            boolean market="markets".equals(row.optString("kind"));ink=market?Color.WHITE:normalInk;
            int bg=market?Color.rgb(16,24,32):Color.TRANSPARENT;if(backgroundColor!=bg){backgroundColor=bg;setBackgroundColor(bg);}
            speed=(float)Math.max(5,Math.min(260,row.optDouble("speed",95)))*getResources().getDisplayMetrics().density;
            expire();if(changed){staticText=null;lastPhrase=SystemClock.elapsedRealtime();invalidate();}updateFrames();
        }
        StaticLayout layout(CharSequence value,int width){return StaticLayout.Builder.obtain(value,0,value.length(),textPaint,Math.max(1,width)).setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).setMaxLines(1).setTextDirection(TextDirectionHeuristics.FIRSTSTRONG_LTR).build();}
        void expire(){if(row==null || getHeight()==0 || getWidth()==0)return;
            float font=Math.max(1,Math.min(dp(28),getHeight()*0.63f));
            ArrayList<JSONObject> eligible=new ArrayList<>();JSONArray values=row.optJSONArray("items");
            StringBuilder key=new StringBuilder().append(font).append('|').append(separator).append('|').append(ink).append('|').append(look);
            if(values!=null)for(int i=0;i<Math.min(40,values.length());i++){JSONObject item=values.optJSONObject(i);if(item==null || (!item.isNull("expiresAt") && item.optDouble("expiresAt",0)<=now()))continue;eligible.add(item);key.append('|').append(item.optString("id")).append(':').append(item.optString("text"));}
            if(!fingerprint.equals(key.toString())){
                String current="";double within=0;
                if(!segments.isEmpty()){Segment old=segments.get(segmentAt(position));current=old.id;within=position-old.start;}
                fingerprint=key.toString();fontPixels=font;textPaint.setTextSize(font);textPaint.setColor(ink);segments.clear();tiles.evictAll();staticText=null;total=0;
                int accent=Color.parseColor("markets".equals(row.optString("kind"))?"#FFC53D":"news".equals(look)?"#C9162D":"#7BADE0");
                String mark="   "+separator+"   ";
                for(int i=0;i<eligible.size();i++){
                    JSONObject item=eligible.get(i);SpannableStringBuilder value=new SpannableStringBuilder(item.optString("text").replace('\n',' ').replace('\r',' '));int at=value.length();value.append(mark);value.setSpan(new ForegroundColorSpan(accent),at,value.length(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    if("▌▌▌".equals(separator)){int[] colours={Color.WHITE,Color.rgb(40,109,204),Color.rgb(227,54,61)};for(int j=0;j<3;j++)value.setSpan(new ForegroundColorSpan(colours[j]),at+3+j,at+4+j,33);}
                    int width=Math.max(1,(int)Math.ceil(Layout.getDesiredWidth(value,textPaint)));segments.add(new Segment(item.optString("id"),layout(value,width),width,total));total+=width;
                }
                position=0;phraseIndex=0;
                for(int i=0;i<segments.size();i++)if(segments.get(i).id.equals(current)){Segment s=segments.get(i);position=s.start+Math.min(Math.max(0,within),s.width-1);phraseIndex=i;break;}
                if(!segments.isEmpty())warmTiles();invalidate();
            }
            if(reduced && playing && !segments.isEmpty() && SystemClock.elapsedRealtime()-lastPhrase>=7000){phraseIndex=(phraseIndex+1)%segments.size();position=segments.get(phraseIndex).start;staticText=null;lastPhrase=SystemClock.elapsedRealtime();invalidate();}
        }
        int segmentAt(double offset){for(int i=segments.size()-1;i>=0;i--)if(offset>=segments.get(i).start)return i;return 0;}
        void advance(double seconds){position=TickerMath.wrap(position+seconds*speed,total);warmTiles();}
        void warmTiles(){if(total<=0)return;long page=(long)Math.floor(position/TILE);int count=(getWidth()+TILE-1)/TILE+2;for(int i=0;i<count;i++)tile(page+i);}
        Bitmap tile(long page){Bitmap image=tiles.get(page);if(image!=null)return image;
            image=Bitmap.createBitmap(TILE,Math.max(1,getHeight()),Bitmap.Config.ARGB_8888);image.setDensity(Bitmap.DENSITY_NONE);Canvas canvas=new Canvas(image);
            double at=TickerMath.wrap(page*(double)TILE,total);int index=segmentAt(at);float x=(float)(segments.get(index).start-at);
            int guard=0;while(x<TILE && guard++<2048){Segment segment=segments.get(index);int save=canvas.save();canvas.translate(x,(getHeight()-segment.layout.getHeight())/2f);segment.layout.draw(canvas);canvas.restoreToCount(save);x+=segment.width;index=(index+1)%segments.size();}
            tiles.put(page,image);return image;
        }
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);
            if(segments.isEmpty() || reduced){
                if(staticText==null){String value=segments.isEmpty()?getResources().getString(R.string.waiting):row.optJSONArray("items")==null?"":findPhrase();textPaint.setTextSize(fontPixels>0?fontPixels:dp(14));textPaint.setColor(ink);staticText=layout(value,getWidth());}
                int save=canvas.save();canvas.translate(0,(getHeight()-staticText.getHeight())/2f);staticText.draw(canvas);canvas.restoreToCount(save);return;
            }
            long page=(long)Math.floor(position/TILE);float shift=(float)(position-page*TILE);int count=(getWidth()+TILE-1)/TILE+1;
            for(int i=0;i<count;i++)canvas.drawBitmap(tile(page+i),i*TILE-shift,0,bitmapPaint);
        }
        String findPhrase(){String id=segments.get(Math.floorMod(phraseIndex,segments.size())).id;JSONArray values=row.optJSONArray("items");if(values!=null)for(int i=0;i<values.length();i++){JSONObject item=values.optJSONObject(i);if(item!=null && id.equals(item.optString("id")))return item.optString("text");}return "";}
        @Override protected void onSizeChanged(int w,int h,int oldW,int oldH){super.onSizeChanged(w,h,oldW,oldH);tiles.resize(Math.max(4,(w+TILE-1)/TILE+3));if(h!=oldH){fingerprint="";tiles.evictAll();staticText=null;}expire();updateFrames();}
    }
}
