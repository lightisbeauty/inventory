import Cocoa
import WebKit

let kCurrentVersion = "26090402"

class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    var installingPanel: NSPanel?

    var autoCheckEnabled: Bool {
        get {
            let stored = UserDefaults.standard.object(forKey: "autoCheckUpdates")
            return stored == nil ? true : UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    func checkOnLaunch() {
        guard autoCheckEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.check(silent: true) }
    }

    @objc func checkNow(_ sender: Any?) { check(silent: false) }

    @objc func toggleAutoCheck(_ sender: NSMenuItem) {
        autoCheckEnabled = !autoCheckEnabled
        sender.state = autoCheckEnabled ? .on : .off
    }

    func check(silent: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/lightisbeauty/inventory/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("inventory/\(kCurrentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                if !silent { DispatchQueue.main.async { self.showError() } }
                return
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgURL = assets.first {
                ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true
            }?["browser_download_url"] as? String
            DispatchQueue.main.async {
                if latest > kCurrentVersion { self.showAvailable(version: latest, url: htmlURL, dmgURL: dmgURL) }
                else if !silent { self.showUpToDate() }
            }
        }.resume()
    }

    func showAvailable(version: String, url: String, dmgURL: String?) {
        let a = NSAlert()
        a.messageText = "Update available"
        a.informativeText = "inventory \(version) is available. You're running \(kCurrentVersion)."
        a.addButton(withTitle: dmgURL != nil ? "Install Update" : "Download")
        a.addButton(withTitle: "Later")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if let dmgURL = dmgURL, let dl = URL(string: dmgURL) {
            installUpdate(from: dl, version: version, fallbackURL: url)
        } else if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }

    func showUpToDate() {
        let a = NSAlert()
        a.messageText = "You're up to date"
        a.informativeText = "inventory \(kCurrentVersion) is the latest version."
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    func showError() {
        let a = NSAlert()
        a.messageText = "Couldn't check for updates"
        a.informativeText = "Make sure you're connected to the internet and try again."
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    // MARK: - Auto-install

    func showInstalling(_ status: String) {
        if let panel = installingPanel {
            (panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first)?.stringValue = status
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 90),
                            styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Updating"
        panel.isFloatingPanel = true
        panel.center()

        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 30, width: 20, height: 20))
        spinner.style = .spinning
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: status)
        label.frame = NSRect(x: 50, y: 34, width: 210, height: 20)

        panel.contentView?.addSubview(spinner)
        panel.contentView?.addSubview(label)
        panel.makeKeyAndOrderFront(nil)
        installingPanel = panel
    }

    func hideInstalling() {
        installingPanel?.close()
        installingPanel = nil
    }

    func run(_ launchPath: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func installUpdate(from dmgURL: URL, version: String, fallbackURL: String) {
        showInstalling("Downloading update…")
        URLSession.shared.downloadTask(with: dmgURL) { tmpURL, response, error in
            guard let tmpURL = tmpURL, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { self.installFailed(fallbackURL: fallbackURL) }
                return
            }
            let dmgPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("inventory-update-\(version).dmg")
            try? FileManager.default.removeItem(at: dmgPath)
            do {
                try FileManager.default.moveItem(at: tmpURL, to: dmgPath)
            } catch {
                DispatchQueue.main.async { self.installFailed(fallbackURL: fallbackURL) }
                return
            }
            self.performInstall(dmgPath: dmgPath, fallbackURL: fallbackURL)
        }.resume()
    }

    func performInstall(dmgPath: URL, fallbackURL: String) {
        DispatchQueue.main.async { self.showInstalling("Installing update…") }
        DispatchQueue.global(qos: .userInitiated).async {
            let mountPoint = FileManager.default.temporaryDirectory
                .appendingPathComponent("inventory-update-mount-\(UUID().uuidString)").path
            try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

            let (attachStatus, _) = self.run("/usr/bin/hdiutil",
                ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint, dmgPath.path])
            guard attachStatus == 0 else {
                DispatchQueue.main.async { self.installFailed(fallbackURL: fallbackURL) }
                return
            }
            defer { _ = self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }

            guard let items = try? FileManager.default.contentsOfDirectory(atPath: mountPoint),
                  let appName = items.first(where: { $0.hasSuffix(".app") }) else {
                DispatchQueue.main.async { self.installFailed(fallbackURL: fallbackURL) }
                return
            }

            let sourceApp = mountPoint + "/" + appName
            let currentAppPath = Bundle.main.bundlePath
            let destDir = (currentAppPath as NSString).deletingLastPathComponent
            let destApp = destDir + "/" + appName
            let backupApp = destApp + ".old"

            // A backup left over from an interrupted previous update means that
            // swap never finished. If the live app is missing, the backup is the
            // only working copy -- restore it rather than deleting it. Otherwise
            // it's just stale cleanup from a completed cycle.
            if FileManager.default.fileExists(atPath: backupApp) {
                if !FileManager.default.fileExists(atPath: destApp) {
                    try? FileManager.default.moveItem(atPath: backupApp, toPath: destApp)
                } else {
                    try? FileManager.default.removeItem(atPath: backupApp)
                }
            }
            do {
                try FileManager.default.moveItem(atPath: destApp, toPath: backupApp)
                try FileManager.default.copyItem(atPath: sourceApp, toPath: destApp)
            } catch {
                // Recover to the last known-good app regardless of what's left at
                // destApp -- a failed copyItem can leave a partial/broken .app
                // there rather than nothing, so don't condition the restore on
                // destApp being absent.
                if FileManager.default.fileExists(atPath: backupApp) {
                    try? FileManager.default.removeItem(atPath: destApp)
                    try? FileManager.default.moveItem(atPath: backupApp, toPath: destApp)
                }
                DispatchQueue.main.async { self.installFailed(fallbackURL: fallbackURL) }
                return
            }
            try? FileManager.default.removeItem(atPath: backupApp)
            // Detach before deleting the backing DMG file — deleting it out from
            // under a still-mounted volume can leave an orphaned mount behind.
            _ = self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
            try? FileManager.default.removeItem(at: dmgPath)

            DispatchQueue.main.async { self.relaunch(appPath: destApp) }
        }
    }

    func relaunch(appPath: String) {
        hideInstalling()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func installFailed(fallbackURL: String) {
        hideInstalling()
        let a = NSAlert()
        a.messageText = "Couldn't install update automatically"
        a.informativeText = "You can download and install it manually instead."
        a.addButton(withTitle: "Open Release Page")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn, let u = URL(string: fallbackURL) {
            NSWorkspace.shared.open(u)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var htmlPath: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        if offerMoveToApplications() { return }
        showScanningWindow()
        DispatchQueue.global(qos: .userInitiated).async {
            self.ensureDependencies()
            self.runScan()
            DispatchQueue.main.async {
                self.loadReport()
                UpdateChecker.shared.checkOnLaunch()
            }
        }
    }

    func offerMoveToApplications() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as NSString? else { return false }
        let appName = Bundle.main.bundlePath.components(separatedBy: "/").last ?? "inventory.app"
        let dest = "/Applications/\(appName)"
        let current = bundlePath as String

        if current.hasPrefix("/Applications") { return false }
        if FileManager.default.fileExists(atPath: dest) { return false }

        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "Would you like to move inventory to your Applications folder?"
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Run from here")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try FileManager.default.moveItem(atPath: current, toPath: dest)
                NSWorkspace.shared.open(URL(fileURLWithPath: dest))
                NSApp.terminate(nil)
                return true
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "Couldn't move to Applications"
                errAlert.informativeText = "You can drag it manually. The app will continue from its current location."
                errAlert.runModal()
            }
        }
        return false
    }

    func showScanningWindow() {
        let rect = NSRect(x: 0, y: 0, width: 960, height: 820)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "inventory"
        window.center()
        window.minSize = NSSize(width: 600, height: 400)

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "nativeExport")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView?.addSubview(webView)

        let loadingHTML = """
        <html><body style="background:#040d1a;color:#888;font-family:-apple-system,sans-serif;
        display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
        <div style="text-align:center"><p style="font-size:18px;color:#41b6e6">Scanning system…</p>
        <p style="font-size:13px;margin-top:8px">This may take a moment</p></div></body></html>
        """
        webView.loadHTMLString(loadingHTML, baseURL: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resourcePath() -> String {
        let bundle = Bundle.main.resourcePath ?? "."
        if FileManager.default.fileExists(atPath: bundle + "/inventory_mac.py") {
            return bundle
        }
        return (ProcessInfo.processInfo.arguments.first.flatMap {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }) ?? "."
    }

    func ensureDependencies() {
        func which(_ cmd: String) -> Bool {
            let paths = [
                "/opt/homebrew/bin/\(cmd)",
                "/usr/local/bin/\(cmd)",
                "/usr/bin/\(cmd)",
                "/bin/\(cmd)"
            ]
            return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
        }

        if !which("brew") {
            let install = showAlert(
                "Homebrew is not installed.",
                info: "It's needed to read your full App Store inventory (app names, versions, and IDs). Without it, the App Store section will be limited or missing.\n\nInstall Homebrew now?",
                buttons: ["Install", "Skip"]
            )
            if install == .alertFirstButtonReturn {
                runTerminalCommand(
                    "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && "
                    + "brew install mas && echo '\\n\\nDone. You can close this window.' && read -rp ''"
                )
                return
            }
        }

        if which("brew") && !which("mas") {
            let brewPath = shellOutput("/usr/bin/env which brew")
            _ = shellOutput("\(brewPath) install mas")
        }
    }

    func showAlert(_ message: String, info: String, buttons: [String]) -> NSApplication.ModalResponse {
        var result: NSApplication.ModalResponse = .alertSecondButtonReturn
        DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = info
            for b in buttons { alert.addButton(withTitle: b) }
            alert.alertStyle = .informational
            result = alert.runModal()
        }
        return result
    }

    func runTerminalCommand(_ cmd: String) {
        let script = "tell application \"Terminal\" to do script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
    }

    func shellOutput(_ cmd: String) -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-l", "-c", cmd]
        var env = ProcessInfo.processInfo.environment
        let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        env["PATH"] = brewPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func runScan() {
        let script = resourcePath() + "/inventory_mac.py"
        let tmpDir = FileManager.default.temporaryDirectory
        htmlPath = tmpDir.appendingPathComponent("inventory_report.html").path
        let output = shellOutput("/usr/bin/env python3 \"\(script)\"")
        try? output.write(toFile: htmlPath, atomically: true, encoding: .utf8)
    }

    func loadReport() {
        let url = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    var snapshotsDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("inventory/snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func snapshotFilename() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyMMdd_HHmm"
        let d = df.string(from: Date())
        let serial = shellOutput("ioreg -l | grep IOPlatformSerialNumber | awk -F'\"' '{print $4}'")
        return "inventory_\(d)_\(serial).html"
    }

    func saveSnapshot(_ html: String) {
        let filename = snapshotFilename()
        let url = snapshotsDir.appendingPathComponent(filename)
        try? html.write(to: url, atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            if let data = try? JSONSerialization.data(withJSONObject: [filename]),
               let json = String(data: data, encoding: .utf8) {
                let arg = json.dropFirst().dropLast()
                self.webView.evaluateJavaScript("showSnapshotSaved(\(arg))")
            }
        }
    }

    func openSnapshots() {
        let dir = snapshotsDir
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: []
        ))?.filter { $0.pathExtension.lowercased() == "html" }
          .sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
          } ?? []
        let list = files.map { ["filename": $0.lastPathComponent] }
        if let data = try? JSONSerialization.data(withJSONObject: list),
           let json = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("receiveSnapshotList(\(json))")
            }
        }
    }

    func deleteSnapshot(_ filename: String) {
        try? FileManager.default.removeItem(at: snapshotsDir.appendingPathComponent(filename))
        openSnapshots()
    }

    func loadSnapshot(_ filename: String) {
        let url = snapshotsDir.appendingPathComponent(filename)
        guard let html = try? String(contentsOf: url, encoding: .utf8) else { return }
        let escaped = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("receiveCompareData(`\(escaped)`, `\(filename)`);")
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        if action == "pdf" { exportPDF() }
        else if action == "html", let html = body["html"] as? String { exportHTML(html) }
        else if action == "saveSnapshot", let html = body["html"] as? String { saveSnapshot(html) }
        else if action == "openSnapshots" { openSnapshots() }
        else if action == "deleteSnapshot", let f = body["filename"] as? String { deleteSnapshot(f) }
        else if action == "loadSnapshot", let f = body["filename"] as? String { loadSnapshot(f) }
        else if action == "compareFromFile" { openCompare() }
    }

    func exportPDF() {
        webView.evaluateJavaScript(
            "document.querySelectorAll('details').forEach(function(d){d.open=true})"
        ) { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = self.exportFilename(ext: "pdf")
                panel.allowedContentTypes = [.pdf]
                panel.begin { response in
                    guard response == .OK, let url = panel.url else {
                        self.webView.evaluateJavaScript(
                            "document.querySelectorAll('details').forEach(function(d){d.open=false}); restoreExportView();"
                        )
                        return
                    }
                    let config = WKPDFConfiguration()
                    self.webView.createPDF(configuration: config) { result in
                        DispatchQueue.main.async {
                            if case .success(let data) = result {
                                try? data.write(to: url)
                                NSWorkspace.shared.open(url)
                            }
                            self.webView.evaluateJavaScript(
                                "document.querySelectorAll('details').forEach(function(d){d.open=false}); restoreExportView();"
                            )
                        }
                    }
                }
            }
        }
    }

    func exportFilename(ext: String) -> String {
        let date = DateFormatter()
        date.dateFormat = "yyMMdd"
        let d = date.string(from: Date())
        let serial = shellOutput("ioreg -l | grep IOPlatformSerialNumber | awk -F'\"' '{print $4}'")
        return "inventory_\(d)_\(serial).\(ext)"
    }

    func exportHTML(_ html: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFilename(ext: "html")
        panel.allowedContentTypes = [.html]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func openCompare() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.message = "Select a previous inventory report to compare"
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let html = try? String(contentsOf: url, encoding: .utf8) else { return }
            let filename = url.lastPathComponent
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(
                    "receiveCompareData(`\(escaped)`, `\(filename)`);"
                )
            }
        }
    }
}

func buildMenuBar() {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "About inventory",
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
    appMenu.addItem(.separator())

    let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(UpdateChecker.checkNow(_:)), keyEquivalent: "")
    checkItem.target = UpdateChecker.shared
    appMenu.addItem(checkItem)

    let autoItem = NSMenuItem(title: "Automatically Check for Updates", action: #selector(UpdateChecker.toggleAutoCheck(_:)), keyEquivalent: "")
    autoItem.target = UpdateChecker.shared
    autoItem.state = UpdateChecker.shared.autoCheckEnabled ? .on : .off
    appMenu.addItem(autoItem)

    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Quit inventory",
                               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let winItem = NSMenuItem()
    let winMenu = NSMenu(title: "Window")
    winMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
    winMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    winItem.submenu = winMenu
    mainMenu.addItem(winItem)

    NSApplication.shared.mainMenu = mainMenu
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
buildMenuBar()
app.run()
