import UIKit

/// Yazboz 101 iPhone kabuğu. Uygulamanın kendisi Web/index.html'dedir (sitedekiyle aynı dosya).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let web = WebViewController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let url = launchOptions?[.url] as? URL { web.pendingLink = url.absoluteString }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = web
        window?.makeKeyAndVisible()
        return true
    }

    /// Siteden "Uygulamada aç": yazboz101://masa/KOD
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        web.deepLink(url.absoluteString)
        return true
    }

    /// QR bağlantısı https://SİTE/m/KOD — Universal Links (ücretli Apple geliştirici hesabı ve Associated Domains gerekir)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let u = userActivity.webpageURL else { return false }
        web.deepLink(u.absoluteString)
        return true
    }
}
