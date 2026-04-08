import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var statusItem: NSStatusItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let width: CGFloat = 440
    let height: CGFloat = 820
    let x = screenFrame.midX - width / 2
    let y = screenFrame.midY - height / 2
    self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    self.minSize = NSSize(width: 380, height: 650)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupStatusBar()
    setupStatusBarChannel(controller: flutterViewController)
    setupNotificationChannel(controller: flutterViewController)

    super.awakeFromNib()
  }

  private func setupStatusBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.button?.title = "🪑 --:--"
    statusItem?.button?.action = #selector(statusBarClicked)
    statusItem?.button?.target = self
  }

  @objc private func statusBarClicked() {
    NSApp.activate(ignoringOtherApps: true)
    self.makeKeyAndOrderFront(nil)
  }

  private func setupStatusBarChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.sitempo/statusbar",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }

      switch call.method {
      case "update":
        if let args = call.arguments as? [String: Any],
           let time = args["time"] as? String,
           let emoji = args["emoji"] as? String {
          DispatchQueue.main.async {
            self.statusItem?.button?.title = "\(emoji) \(time)"
          }
          result(nil)
        } else {
          result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
        }

      case "clear":
        DispatchQueue.main.async {
          self.statusItem?.button?.title = "🪑 --:--"
        }
        result(nil)

      case "bringToFront":
        DispatchQueue.main.async {
          NSApp.activate(ignoringOtherApps: true)
          NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupNotificationChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.sitempo/notifications",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "checkPermission":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let status: String
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral:
            status = "granted"
          case .denied:
            status = "denied"
          case .notDetermined:
            fallthrough
          @unknown default:
            status = "notDetermined"
          }
          DispatchQueue.main.async { result(status) }
        }

      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound]
        ) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }

      case "show":
        if let args = call.arguments as? [String: Any],
           let title = args["title"] as? String {
          let body = args["body"] as? String ?? ""

          let content = UNMutableNotificationContent()
          content.title = title
          content.body = body
          content.sound = .default

          let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
          )

          UNUserNotificationCenter.current().add(request) { _ in
            DispatchQueue.main.async { result(nil) }
          }
        } else {
          result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
