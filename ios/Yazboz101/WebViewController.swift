import UIKit
import WebKit
import Vision
import PhotosUI

/// WKWebView'i açar ve sayfaya "yazboz" adıyla şu yetenekleri verir:
///   {cmd: 'scan', source: 'camera'|'gallery'} → fotoğraf alır, Apple Vision ile yazıları okur, ybNative.scanDone({w,h,img,items})
///   {cmd: 'ocr', img: dataURL}                → sayfanın hazırladığı siyah-beyaz taş sayfasını okur, ybNative.ocrDone({items})
/// Gece modu adres satırıyla (#t=dark) ve değişince ybNative.theme() ile, derin bağlantılar (&yz=) ve ybNative.deepLink() ile iletilir.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate,
                               UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
    private var webView: WKWebView!
    private var loaded = false
    private var queued: [String] = []
    var pendingLink: String?
    #if DEBUG
    private var testStarted = false
    #endif

    override func loadView() {
        let conf = WKWebViewConfiguration()
        conf.userContentController.add(WeakHandler(self), name: "yazboz")
        #if DEBUG
        // Sadece test sürümünde: sayfadaki hatalar kayda geçer (mağaza sürümüne girmez)
        conf.userContentController.addUserScript(WKUserScript(source: Self.consoleHook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        // Yerel dosyadan canlı skor sunucusuna (Firebase) bağlanabilmek için
        conf.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        conf.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        webView = WKWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = self
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.075, green: 0.478, blue: 0.337, alpha: 1)
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let dir = Bundle.main.url(forResource: "Web", withExtension: nil) else { return }
        let index = dir.appendingPathComponent("index.html")
        var frag = "t=" + (traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
        if let l = pendingLink {
            frag += "&yz=" + (l.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            pendingLink = nil
        }
        let url = URL(string: index.absoluteString + "#" + frag) ?? index
        webView.loadFileURL(url, allowingReadAccessTo: dir)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            run("ybNative.theme('" + (traitCollection.userInterfaceStyle == .dark ? "dark" : "light") + "')")
        }
    }

    // MARK: sayfayla konuşma

    func deepLink(_ s: String) { run("ybNative.deepLink(" + jsString(s) + ")") }

    private func run(_ code: String) {
        DispatchQueue.main.async {
            if self.loaded { self.webView.evaluateJavaScript("window.ybNative && " + code, completionHandler: nil) }
            else { self.queued.append(code) }
        }
    }

    private func jsString(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]), let a = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(a.dropFirst().dropLast())
    }

    private func send(_ fn: String, _ o: [String: Any], fail: String) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { run(fail); return }
        run("ybNative.\(fn)(" + jsString(s) + ")")
    }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        queued.forEach { webView.evaluateJavaScript("window.ybNative && " + $0, completionHandler: nil) }
        queued.removeAll()
        #if DEBUG
        startTestIfNeeded()
        #endif
    }

    /// Dış bağlantılar (indirme sayfası vb.) Safari'de açılır
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, let sc = u.scheme?.lowercased(), sc == "http" || sc == "https" {
            UIApplication.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let cmd = b["cmd"] as? String else { return }
        #if DEBUG
        if cmd == "log" { testLog(b["msg"] as? String ?? ""); return }
        if cmd == "shot", let n = b["name"] as? String { testShot(n); return }
        #endif
        if cmd == "scan" { scan(source: b["source"] as? String ?? "gallery") }
        else if cmd == "ocr", let s = b["img"] as? String { ocr(dataURL: s) }
    }

    // MARK: fotoğraf

    private func scan(source: String) {
        if source == "camera" {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { run("ybNative.scanFail('no_camera')"); return }
            let p = UIImagePickerController()
            p.sourceType = .camera
            p.delegate = self
            present(p, animated: true)
        } else {
            var cfg = PHPickerConfiguration()
            cfg.filter = .images
            cfg.selectionLimit = 1
            let p = PHPickerViewController(configuration: cfg)
            p.delegate = self
            present(p, animated: true)
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else { run("ybNative.scanFail('fail')"); return }
        process(img)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        run("ybNative.scanFail('cancelled')")
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let prov = results.first?.itemProvider, prov.canLoadObject(ofClass: UIImage.self) else { run("ybNative.scanFail('cancelled')"); return }
        prov.loadObject(ofClass: UIImage.self) { obj, _ in
            guard let img = obj as? UIImage else { self.run("ybNative.scanFail('fail')"); return }
            self.process(img)
        }
    }

    private func process(_ img: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cg = self.upright(img, maxSide: 1600) else { self.run("ybNative.scanFail('fail')"); return }
            self.recognize(cg) { items in
                let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
                self.send("scanDone", ["w": cg.width, "h": cg.height, "img": "data:image/jpeg;base64," + jpeg, "items": items], fail: "ybNative.scanFail('fail')")
            }
        }
    }

    private func ocr(dataURL: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let comma = dataURL.firstIndex(of: ","),
                  let d = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
                  let ui = UIImage(data: d), let cg = ui.cgImage else { self.run("ybNative.ocrFail('fail')"); return }
            self.recognize(cg) { items in self.send("ocrDone", ["items": items], fail: "ybNative.ocrFail('fail')") }
        }
    }

    /// Fotoğrafı dik çevirip en uzun kenarı en çok maxSide piksel olacak şekilde küçültür
    private func upright(_ img: UIImage, maxSide: CGFloat) -> CGImage? {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * s).rounded(), height: (img.size.height * s).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    /// Apple Vision ile metin tanıma; her sözcük için piksel kutusu (sol üst köşe başlangıçlı)
    private func recognize(_ cg: CGImage, done: @escaping ([[String: Any]]) -> Void) {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let req = VNRecognizeTextRequest { r, _ in
            var items: [[String: Any]] = []
            for obs in (r.results as? [VNRecognizedTextObservation]) ?? [] {
                guard let c = obs.topCandidates(1).first else { continue }
                let s = c.string
                var from = s.startIndex
                for part in s.split(separator: " ") {
                    guard let rg = s.range(of: String(part), range: from..<s.endIndex) else { continue }
                    from = rg.upperBound
                    guard let bb = try? c.boundingBox(for: rg)?.boundingBox else { continue }
                    items.append(["t": String(part), "x": bb.minX * W, "y": (1 - bb.maxY) * H, "w": bb.width * W, "h": bb.height * H])
                }
            }
            done(items)
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req]) } catch { done([]) }
    }
}

/// Mesaj işleyicisinin denetleyiciyi bellekte tutmaması için
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

#if DEBUG
/// Otomatik test (GitHub'daki iPhone simülatörü): YAZBOZ_TEST ortam değişkeniyle gelen senaryoyu çalıştırır,
/// ekran görüntülerini ve sonucu uygulamanın Belgeler/test klasörüne yazar. Mağaza (Release) sürümüne girmez.
extension WebViewController {
    static let consoleHook = """
    (function(){function p(k,a){try{window.webkit.messageHandlers.yazboz.postMessage({cmd:'log',msg:k+': '+Array.prototype.map.call(a,function(x){try{return x&&x.stack?x.stack:(typeof x==='object'?JSON.stringify(x):String(x))}catch(e){return String(x)}}).join(' ')})}catch(e){}}
    ['error','warn'].forEach(function(k){var o=console[k];console[k]=function(){p(k,arguments);return o.apply(console,arguments)}});
    addEventListener('error',function(e){p('hata',[e.message+' @'+e.filename+':'+e.lineno])});
    addEventListener('unhandledrejection',function(e){p('promise',[e.reason])});})();
    """

    private var testDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("test")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    fileprivate func testLog(_ s: String) {
        NSLog("YAZBOZ %@", s)
        let f = testDir.appendingPathComponent("konsol.txt")
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(line); h.closeFile() } else { try? line.write(to: f) }
    }

    fileprivate func testShot(_ name: String) {
        let cfg = WKSnapshotConfiguration()
        cfg.afterScreenUpdates = true
        webView.takeSnapshot(with: cfg) { img, _ in
            let safe = name.replacingOccurrences(of: "/", with: "-")
            if let d = img?.pngData() { try? d.write(to: self.testDir.appendingPathComponent(safe + ".png")) }
            self.webView.evaluateJavaScript("window.__ybShotDone && window.__ybShotDone(" + self.jsString(name) + ")", completionHandler: nil)
        }
    }

    fileprivate func startTestIfNeeded() {
        guard !testStarted, let sc = ProcessInfo.processInfo.environment["YAZBOZ_TEST"], !sc.isEmpty else { return }
        testStarted = true
        let body = sc + "\n;return await window.__ybRun('ios', function (n) { window.webkit.messageHandlers.yazboz.postMessage({cmd: 'shot', name: n}); });"
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { r in
            var text = "{\"ok\":false,\"hata\":\"sonuç boş\"}"
            switch r {
            case .success(let v): if let t = v as? String { text = t }
            case .failure(let e): text = "{\"ok\":false,\"hata\":" + self.jsString(e.localizedDescription) + "}"
            }
            try? text.write(to: self.testDir.appendingPathComponent("sonuc.json"), atomically: true, encoding: .utf8)
        }
    }
}
#endif
