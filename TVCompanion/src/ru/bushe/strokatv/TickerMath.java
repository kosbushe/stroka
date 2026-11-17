package ru.bushe.strokatv;

final class TickerMath {
    private TickerMath(){}
    static double wrap(double position,double length){
        if(!Double.isFinite(position) || !Double.isFinite(length) || length<=0)return 0;
        double result=position%length;return result<0?result+length:result;
    }
}
