#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

struct QRScanner:UIViewControllerRepresentable {
    let found:(String)->Void
    func makeUIViewController(context:Context)->CameraScanner {CameraScanner(found:found)}
    func updateUIViewController(_ controller:CameraScanner,context:Context){}
    static func dismantleUIViewController(_ controller:CameraScanner,coordinator:()){controller.stop()}
}
final class CameraScanner:UIViewController,AVCaptureMetadataOutputObjectsDelegate {
    let found:(String)->Void
    let session=AVCaptureSession()
    let worker=DispatchQueue(label:"stroka.qr.camera")
    var preview:AVCaptureVideoPreviewLayer?
    var reported=false
    private var stopped=false
    private let stopLock=NSLock()
    private func isStopped()->Bool{stopLock.lock();defer{stopLock.unlock()};return stopped}
    init(found:@escaping(String)->Void){self.found=found;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder){fatalError("Not used")}
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for:.video){
        case .authorized:configure()
        case .notDetermined:AVCaptureDevice.requestAccess(for:.video){allowed in DispatchQueue.main.async{if allowed{self.configure()}else{self.denied()}}}
        default:denied()
        }
    }
    func denied(){let label=UILabel();label.text="Разрешите камеру для Stroka в Настройках iPhone. Или используйте ссылку подключения.";label.textColor = .white;label.numberOfLines=0;label.textAlignment = .center;label.frame=view.bounds.insetBy(dx:28,dy:80);label.autoresizingMask=[.flexibleWidth,.flexibleHeight];view.addSubview(label)}
    func configure(){
        worker.async{
            guard !self.isStopped() else{return}
            guard let camera=AVCaptureDevice.default(for:.video),let input=try? AVCaptureDeviceInput(device:camera),self.session.canAddInput(input) else{DispatchQueue.main.async{self.denied()};return}
            self.session.beginConfiguration();self.session.addInput(input)
            let output=AVCaptureMetadataOutput();guard self.session.canAddOutput(output)else{self.session.commitConfiguration();return}
            self.session.addOutput(output);output.setMetadataObjectsDelegate(self,queue:.main);output.metadataObjectTypes=[.qr];self.session.commitConfiguration()
            DispatchQueue.main.async{
                guard !self.isStopped() else{return}
                let layer=AVCaptureVideoPreviewLayer(session:self.session);layer.videoGravity = .resizeAspectFill;layer.frame=self.view.bounds;self.view.layer.insertSublayer(layer,at:0);self.preview=layer
                let label=UILabel();label.text="Наведите камеру на QR в Stroka TV";label.textColor = .white;label.textAlignment = .center;label.frame=CGRect(x:10,y:50,width:self.view.bounds.width-20,height:60);label.autoresizingMask=[.flexibleWidth];self.view.addSubview(label)
            }
            if !self.isStopped(){self.session.startRunning()}
        }
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();preview?.frame=view.bounds}
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput objects:[AVMetadataObject],from connection:AVCaptureConnection){
        guard !reported,let value=objects.compactMap({($0 as? AVMetadataMachineReadableCodeObject)?.stringValue}).first else{return}
        reported=true;stop();found(value)
    }
    func stop(){stopLock.lock();stopped=true;stopLock.unlock();worker.async{if self.session.isRunning{self.session.stopRunning()}}}
}
#endif
