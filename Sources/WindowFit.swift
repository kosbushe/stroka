import AppKit
import SwiftUI

extension AppModel {
    var windowFitHelperURL:URL {Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Stroka Windows.app")}
    var windowFitAvailable:Bool {FileManager.default.fileExists(atPath:windowFitHelperURL.path)}
    func synchronizeWindowFit(showPermission:Bool = false) {
        // Diagnostics never launch a privileged helper or change real windows.
        #if STROKA_DIAGNOSTICS
        return
        #else
        guard windowFitAvailable,let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else{return}
        let directory = support.appendingPathComponent("Stroka",isDirectory:true)
        let url = directory.appendingPathComponent("window-fit.json")
        guard let screen = outputs.window?.screen ?? screens.dropFirst(max(0,selectedScreen)).first ?? screens.first else{return}
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let enabled = settings.fitWindows == true && activeMode == .strip
        let config = WindowFitConfiguration(enabled:enabled,ownerPID:ProcessInfo.processInfo.processIdentifier,ownerBundlePath:Bundle.main.bundleURL.path,screenID:id,top:settings.desktopEdge == .top,height:Double(outputs.window?.frame.height ?? CGFloat(settings.resolvedStripHeight)),language:interfaceLanguage.rawValue)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONEncoder().encode(config).write(to:url,options:.atomic)
            if enabled || showPermission {
                let launch = NSWorkspace.OpenConfiguration();launch.activates = showPermission
                launch.arguments = ["--config",url.path]+(showPermission ? ["--permission"]:[])
                NSWorkspace.shared.openApplication(at:windowFitHelperURL,configuration:launch)
            }
        } catch {NSLog("Stroka window fitting configuration could not be saved")}
        #endif
    }
}
struct WindowFitControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Toggle(L("Keep windows clear of ticker"),isOn:Binding(get:{model.settings.fitWindows == true},set:{model.settings.fitWindows = $0})).disabled(!model.windowFitAvailable)
            Text(L("Fits ordinary windows when you switch apps or resize them. Full Screen and fixed-size windows are excluded. Original sizes return when you stop the ticker, unless you moved the window yourself.")).font(.caption).foregroundStyle(.secondary)
            if model.windowFitAvailable {
                Button(L("Allow window control…")){model.synchronizeWindowFit(showPermission:true)}
            } else {Text(L("Window fitting is available in the direct-download Mac build.")).font(.caption).foregroundStyle(.secondary)}
        }
    }
}
