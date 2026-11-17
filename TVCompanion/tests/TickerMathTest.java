package ru.bushe.strokatv;

public final class TickerMathTest {
    static int checks;
    static void near(double actual,double expected,String label){if(Math.abs(actual-expected)>0.000001)throw new AssertionError(label+": "+actual+" != "+expected);checks++;}
    public static void main(String[] args){
        double speed=317.25,length=2187;
        // Equal elapsed time must produce equal distance at different actual frame cadences.
        for(int fps:new int[]{24,30,50,60,120}){
            double position=0;for(int i=0;i<fps*30;i++)position=TickerMath.wrap(position+speed/fps,length);
            near(position,(speed*30)%length,"frame-rate independent travel at "+fps);
        }
        double position=0,seconds=0;double[] intervals={0.016,0.033,0.017,0.100,0.008,0.026};
        for(int i=0;i<5000;i++){double dt=intervals[i%intervals.length];seconds+=dt;position=TickerMath.wrap(position+speed*dt,length);}
        near(position,(speed*seconds)%length,"missed-frame cadence preserves wall-clock speed");
        near(TickerMath.wrap(length, length),0,"exact seam");near(TickerMath.wrap(length+0.25,length),0.25,"fractional seam");near(TickerMath.wrap(-0.25,length),length-0.25,"backward phase");
        near(TickerMath.wrap(Double.NaN,length),0,"invalid phase is bounded");near(TickerMath.wrap(42,0),0,"empty stream is bounded");
        System.out.println(checks+" ticker timing and seam checks passed");
    }
}
