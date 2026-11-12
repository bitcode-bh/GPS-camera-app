import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CameraAdjustments") else { return }
    FlutterMethodChannel(
      name: "com.gpscamera.gps_camera_next/adjustments",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let id = args["camera"] as? String,
            let device = AVCaptureDevice(uniqueID: id) else {
        result(FlutterError(code: "CAMERA_CLOSED", message: nil, details: nil))
        return
      }
      switch call.method {
      case "features":
        result([
          "flash": device.hasFlash || device.hasTorch,
          "whiteBalanceLock": device.isWhiteBalanceModeSupported(.locked) &&
            device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
        ])
      case "setWhiteBalanceLock":
        guard let locked = args["locked"] as? Bool else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
          return
        }
        let mode: AVCaptureDevice.WhiteBalanceMode = locked ? .locked : .continuousAutoWhiteBalance
        guard device.isWhiteBalanceModeSupported(mode) else {
          result(FlutterError(code: "WHITE_BALANCE_UNAVAILABLE", message: nil, details: nil))
          return
        }
        do {
          try device.lockForConfiguration()
          defer { device.unlockForConfiguration() }
          device.whiteBalanceMode = mode
          result(nil)
        } catch {
          result(FlutterError(code: "WHITE_BALANCE_FAILED", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
