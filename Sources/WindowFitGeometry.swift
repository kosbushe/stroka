import Foundation
import CoreGraphics

// Shared with the separately permissioned desktop helper. Coordinates are Cocoa
// global screen coordinates here, AX top-left coordinates only at the boundary.
struct WindowFitConfiguration:Codable {
    var enabled:Bool
    var ownerPID:Int32
    var ownerBundlePath:String
    var screenID:UInt32
    var top:Bool
    var height:Double
    var language:String
}
enum WindowFitGeometry {
    static func available(_ visible:CGRect,height:CGFloat,top:Bool)->CGRect {
        let h = min(max(0,height),visible.height)
        return CGRect(x:visible.minX,y:visible.minY+(top ? 0:h),width:visible.width,height:visible.height-h)
    }
    static func fit(_ frame:CGRect,in area:CGRect)->CGRect? {
        guard frame.width>0,frame.height>0,area.width>0,area.height>0,
              frame.maxX>area.minX,frame.minX<area.maxX else{return nil}
        var result = frame
        result.size.height = min(frame.height,area.height)
        result.origin.y = min(max(frame.minY,area.minY),area.maxY-result.height)
        return result
    }
    static func flip(_ frame:CGRect,primaryTop:CGFloat)->CGRect {
        CGRect(x:frame.minX,y:primaryTop-frame.maxY,width:frame.width,height:frame.height)
    }
    static func equal(_ a:CGRect,_ b:CGRect)->Bool {
        abs(a.minX-b.minX)<1 && abs(a.minY-b.minY)<1 && abs(a.width-b.width)<1 && abs(a.height-b.height)<1
    }
}
