import Cocoa
import Foundation

// MARK: - Config

struct Config {
    var filePath: String = NSHomeDirectory() + "/.notch-color"
    var interval: Double = 10.0

    static func fromArgs(_ args: [String]) -> Config {
        var cfg = Config()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--file" where i + 1 < args.count:
                cfg.filePath = (args[i + 1] as NSString).expandingTildeInPath
                i += 1
            case "--interval" where i + 1 < args.count:
                if let v = Double(args[i + 1]), v > 0 { cfg.interval = v }
                i += 1
            case "--help", "-h":
                print("""
                NotchGlow — notch status indicator
                Usage: NotchGlow [--file <path>] [--interval <seconds>]
                Defaults: --file ~/.notch-color --interval 10
                File content: RED | GREEN | YELLOW | #RRGGBB | CLEAR (or empty)
                """)
                exit(0)
            default:
                break
            }
            i += 1
        }
        return cfg
    }
}

// MARK: - Color parsing

func parseColor(_ raw: String) -> NSColor? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    switch s {
    case "RED": return .systemRed
    case "GREEN": return .systemGreen
    case "YELLOW": return .systemYellow
    case "ORANGE": return .systemOrange
    case "BLUE": return .systemBlue
    case "PURPLE": return .systemPurple
    case "", "CLEAR", "NONE", "OFF": return nil
    default:
        if s.hasPrefix("#"), s.count == 7,
           let rgb = Int(s.dropFirst(), radix: 16) {
            return NSColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgb & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
        return nil
    }
}

// MARK: - Notch geometry

/// Returns the notch rectangle in screen coordinates, or nil if this screen has no notch.
func notchRect(for screen: NSScreen) -> NSRect? {
    guard #available(macOS 12.0, *),
          let left = screen.auxiliaryTopLeftArea,
          let right = screen.auxiliaryTopRightArea,
          screen.safeAreaInsets.top > 0 else { return nil }
    let x = left.maxX
    let width = right.minX - left.maxX
    let height = screen.safeAreaInsets.top
    return NSRect(x: x, y: screen.frame.maxY - height, width: width, height: height)
}

func notchScreen() -> (NSScreen, NSRect)? {
    for screen in NSScreen.screens {
        if let rect = notchRect(for: screen) { return (screen, rect) }
    }
    return nil
}

// MARK: - Overlay view

final class NotchBorderView: NSView {
    var color: NSColor?
    var notch: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let color = color, !notch.isEmpty else { return }
        // Notch rectangle is in screen coords; convert to view (window) coords.
        let rect = notch.insetBy(dx: -2.5, dy: -2.5)
        let radius: CGFloat = 9
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = 5
        // Outer glow pass
        color.withAlphaComponent(0.35).setStroke()
        let glow = NSBezierPath(roundedRect: notch.insetBy(dx: -5.5, dy: -5.5), xRadius: 12, yRadius: 12)
        glow.lineWidth = 2
        glow.stroke()
        // Main border
        color.setStroke()
        path.stroke()
    }
}

// MARK: - Overlay window

final class OverlayWindowController {
    private var window: NSWindow?
    private let borderView = NotchBorderView(frame: .zero)
    private(set) var color: NSColor? {
        didSet { update() }
    }

    func set(color: NSColor?) {
        self.color = color
    }

    private func update() {
        guard let color = color, let (screen, notch) = notchScreen() else {
            window?.orderOut(nil)
            return
        }
        let frame = screen.frame
        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            borderView.frame = NSRect(origin: .zero, size: frame.size)
            w.contentView = borderView
            window = w
        }
        window?.setFrame(frame, display: true)
        borderView.frame = NSRect(origin: .zero, size: frame.size)
        borderView.color = color
        borderView.notch = notch
        window?.orderFrontRegardless()
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var config: Config!
    private var statusItem: NSStatusItem!
    private let overlay = OverlayWindowController()
    private var timer: Timer?
    private var currentColorName: String = "—"
    private var lastRaw: String?
    private var intervalItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startTimer()
        poll()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        overlay.set(color: overlay.color)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: config.interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let raw = (try? String(contentsOfFile: config.filePath, encoding: .utf8)) ?? ""
        guard raw != lastRaw else { return }
        lastRaw = raw
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = parseColor(raw) {
            currentColorName = trimmed.uppercased()
            overlay.set(color: color)
        } else if trimmed.isEmpty || ["CLEAR", "NONE", "OFF"].contains(trimmed.uppercased()) {
            currentColorName = "—"
            overlay.set(color: nil)
        } else {
            FileHandle.standardError.write("NotchGlow: unrecognized color '\(trimmed)', ignoring\n".data(using: .utf8)!)
        }
        statusItem.menu?.item(at: 0)?.title = "Color: \(currentColorName)"
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "NotchGlow")
        }

        let menu = NSMenu()
        let statusLine = NSMenuItem(title: "Color: —", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(NSMenuItem.separator())

        let info = NSMenuItem(title: "Watching: \(config.filePath)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let intervalMenu = NSMenu()
        for seconds in [1.0, 5.0, 10.0, 30.0, 60.0] {
            let item = NSMenuItem(title: "\(Int(seconds))s", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = (seconds == config.interval) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        intervalItem?.submenu = intervalMenu
        menu.addItem(intervalItem!)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit NotchGlow", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        config.interval = seconds
        intervalItem?.submenu?.items.forEach { $0.state = ($0 == sender) ? .on : .off }
        startTimer()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Entry point

let config = Config.fromArgs(Array(CommandLine.arguments.dropFirst()))
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
delegate.config = config
app.delegate = delegate
app.run()
