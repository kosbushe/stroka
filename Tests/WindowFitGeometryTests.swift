import Foundation
import CoreGraphics

@main enum WindowFitGeometryTests {
    static func main() {
        var count = 0
        func check(_ ok:Bool,_ name:String){guard ok else{fatalError(name)};count += 1;print("PASS: \(name)")}
        let desktop = CGRect(x:0,y:30,width:1440,height:870)
        let bottom = WindowFitGeometry.available(desktop,height:84,top:false)
        let top = WindowFitGeometry.available(desktop,height:84,top:true)
        check(bottom == CGRect(x:0,y:114,width:1440,height:786),"bottom strip reserves exactly its height above the Dock")
        check(top == CGRect(x:0,y:30,width:1440,height:786),"top strip reserves space below the menu bar")
        for height in [45,84,180] {
            let area = WindowFitGeometry.available(desktop,height:CGFloat(height),top:false)
            let fill = WindowFitGeometry.fit(desktop,in:area)!
            check(fill == area,"a filled window leaves a \(height) point strip clear")
            check(WindowFitGeometry.fit(fill,in:area) == fill,"fitting is stable without repeated movement at \(height) points")
        }
        let small = CGRect(x:400,y:50,width:700,height:300)
        check(WindowFitGeometry.fit(small,in:bottom) == CGRect(x:400,y:114,width:700,height:300),"a small overlapping window moves without shrinking")
        let safe = CGRect(x:100,y:200,width:700,height:300)
        check(WindowFitGeometry.fit(safe,in:bottom) == safe,"a window already clear of the ticker stays put")
        check(WindowFitGeometry.fit(CGRect(x:200,y:400,width:900,height:500),in:top) == CGRect(x:200,y:316,width:900,height:500),"top ticker preserves window size when it can fit")
        check(WindowFitGeometry.fit(CGRect(x:1440,y:10,width:800,height:600),in:bottom) == nil,"another display is excluded")
        check(WindowFitGeometry.fit(.zero,in:bottom) == nil,"invalid window bounds are excluded")
        let external = CGRect(x:-1920,y:-280,width:1920,height:1080)
        let externalArea = WindowFitGeometry.available(external,height:84,top:false)
        check(WindowFitGeometry.fit(external,in:externalArea) == externalArea,"negative-origin external displays reserve the correct edge")
        let ax = WindowFitGeometry.flip(external,primaryTop:932)
        check(WindowFitGeometry.flip(ax,primaryTop:932) == external,"AX conversion round-trips displays above and below the primary screen")
        let original = CGRect(x:0,y:30,width:1440,height:870)
        let applied = WindowFitGeometry.fit(original,in:bottom)!
        check(WindowFitGeometry.equal(applied,applied),"untouched fitted bounds qualify for restoration")
        check(!WindowFitGeometry.equal(applied,CGRect(x:120,y:140,width:900,height:600)),"manually rearranged bounds do not qualify for restoration")
        print("\(count) window fitting geometry checks passed")
    }
}
