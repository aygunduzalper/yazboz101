package com.yazboz101.app;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.PackageInfo;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Insets;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import androidx.core.content.FileProvider;
import androidx.exifinterface.media.ExifInterface;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;

/**
 * Yazboz 101 telefon kabuğu: uygulamanın kendisi assets/index.html'dedir (sitedekiyle aynı dosya).
 * Bu sınıf yalnızca WebView'i açar ve sayfaya "YazbozAndroid" adıyla şu yetenekleri verir:
 *   scan('camera'|'gallery')  → fotoğraf alır, ML Kit ile yazıları okur, ybNative.scanDone({w,h,img,items}) çağırır
 *   ocr(dataURL)              → sayfanın hazırladığı siyah-beyaz taş sayfasını okur, ybNative.ocrDone({items}) çağırır
 *   bars('light'|'dark')      → uygulamanın teması değişince durum/gezinme çubuğu renklerini ona uydurur
 * Gece modu adres satırıyla (#t=dark) ve değişince ybNative.theme() ile, derin bağlantılar (&yz=) ve ybNative.deepLink() ile iletilir.
 *
 * Android 15+ (hedef API 35/36): pencere kenardan kenara çizilir; durum çubuğu ve gezinme çubuğu boşluğunu burada bırakıyoruz.
 * Android 16 (hedef API 36): geri tuşu onBackPressed yerine OnBackInvokedCallback ile gelir (tahminli geri hareketi).
 */
public class MainActivity extends Activity {
    private static final int REQ_SCAN = 11, REQ_FILE = 12;
    // Uygulamadaki renklerle aynı: --felt1 (üst şerit) ve --bg (zemin)
    private static final int FELT_LIGHT = 0xff15805c, FELT_DARK = 0xff125a44, BG_LIGHT = 0xffebe8e0, BG_DARK = 0xff0e1211;

    private WebView web;
    private FrameLayout root;
    private View topBar;
    private TextRecognizer recognizer;
    private Uri cameraUri;
    private ValueCallback<Uri[]> fileCb;
    private String barTheme;
    private Object backCb;      // API 33+: OnBackInvokedCallback (eski telefonlarda sınıf yüklenmesin diye Object)
    private boolean backOn;
    private volatile boolean pageReady; // sayfa açılınca YazbozAndroid.ready() ile gelir
    private boolean reloaded, pageFinished;
    private final StringBuilder diag = new StringBuilder(); // açılmazsa gösterilecek hata notları

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowUniversalAccessFromFileURLs(true); // canlı skor sunucusuna (Firebase) yerel dosyadan bağlanabilmek için
        web.addJavascriptInterface(new Bridge(), "YazbozAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { return openOutside(r.getUrl()); }

            @Override
            public void doUpdateVisitedHistory(WebView v, String url, boolean reload) { syncBack(); }

            // Sayfayı çizen süreç çökerse uygulama kapanmasın, ekranı baştan kur
            @Override
            public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail d) { note("Çizim süreci kapandı"); recreate(); return true; }

            @Override
            public void onPageFinished(WebView v, String url) { pageFinished = true; }

            @Override
            public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                if (r.isForMainFrame()) note("Sayfa yüklenemedi: " + e.getDescription() + " (" + e.getErrorCode() + ")");
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                if (m.messageLevel() == ConsoleMessage.MessageLevel.ERROR) note("JS: " + m.message() + " @" + m.lineNumber());
                return false;
            }

            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (fileCb != null) fileCb.onReceiveValue(null);
                fileCb = cb;
                try { startActivityForResult(p.createIntent(), REQ_FILE); }
                catch (ActivityNotFoundException e) { fileCb = null; return false; }
                return true;
            }
        });

        root = new FrameLayout(this);
        root.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        topBar = new View(this);
        root.addView(topBar, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, Gravity.TOP));
        setContentView(root);
        setupInsets();
        applyBars(night() ? "dark" : "light");

        String url = "file:///android_asset/index.html#t=" + (night() ? "dark" : "light");
        Uri d = getIntent() != null ? getIntent().getData() : null;
        if (d != null) url += "&yz=" + Uri.encode(d.toString());
        web.loadUrl(url);
        // Gözcü: sayfa 10 saniyede açıldığını bildirmezse bir kez yeniden yükle; yine açılmazsa nedenini göster
        web.postDelayed(this::watchdog, 10000);
    }

    private void note(String m) {
        synchronized (diag) { if (diag.length() < 1500) diag.append("• ").append(m).append('\n'); }
    }

    private void watchdog() {
        if (pageReady || web == null || isFinishing()) return;
        if (!reloaded) { reloaded = true; web.reload(); web.postDelayed(this::watchdog, 10000); return; }
        String wv = "?";
        if (Build.VERSION.SDK_INT >= 26) wv = webViewVersion();
        String text;
        synchronized (diag) {
            text = "Uygulama ekranı yüklenemedi. Bu pencerenin ekran görüntüsünü destek@yazboz101.com adresine gönderirsen düzeltebiliriz.\n\n"
                    + "Sayfa bitti: " + pageFinished + " · Android " + Build.VERSION.SDK_INT + " · WebView " + wv + " · Sürüm 1.0.1\n"
                    + (diag.length() > 0 ? diag.toString() : "• Hata kaydı yok");
        }
        new AlertDialog.Builder(this)
                .setTitle("Yazboz 101 açılamadı")
                .setMessage(text)
                .setPositiveButton("Tekrar dene", (d, w) -> { pageReady = false; web.reload(); web.postDelayed(this::watchdog, 10000); })
                .setNegativeButton("Kapat", null)
                .show();
    }

    @TargetApi(26)
    private static String webViewVersion() {
        try { PackageInfo p = WebView.getCurrentWebViewPackage(); return p == null ? "yok" : p.packageName + " " + p.versionName; }
        catch (Throwable t) { return "?"; }
    }

    private boolean night() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    }

    /** Uygulama içi bağlantılar (gizlilik, destek, indirme sayfası…) telefonun tarayıcısında açılır */
    private boolean openOutside(Uri u) {
        String sc = u.getScheme();
        if (sc == null || "file".equals(sc) || "about".equals(sc) || "data".equals(sc) || "javascript".equals(sc)) return false;
        try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (ActivityNotFoundException ignored) { }
        return true;
    }

    // ---------- kenardan kenara: çubukların altında kalmamak için boşluk ----------

    private void setupInsets() {
        if (Build.VERSION.SDK_INT < 30) return; // eski sürümlerde sistem kendisi boşluk bırakır
        insets30();
    }

    @TargetApi(30)
    private void insets30() {
        getWindow().setDecorFitsSystemWindows(false);
        root.setOnApplyWindowInsetsListener((v, ins) -> {
            Insets b = ins.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) web.getLayoutParams();
            if (lp.leftMargin != b.left || lp.topMargin != b.top || lp.rightMargin != b.right || lp.bottomMargin != b.bottom) {
                lp.setMargins(b.left, b.top, b.right, b.bottom);
                web.setLayoutParams(lp);
            }
            ViewGroup.LayoutParams tp = topBar.getLayoutParams();
            if (tp.height != b.top) { tp.height = b.top; topBar.setLayoutParams(tp); }
            return WindowInsets.CONSUMED;
        });
    }

    private void applyBars(String t) {
        if (t.equals(barTheme)) return;
        barTheme = t;
        boolean dark = "dark".equals(t);
        int felt = dark ? FELT_DARK : FELT_LIGHT, bg = dark ? BG_DARK : BG_LIGHT;
        root.setBackgroundColor(bg);
        topBar.setBackgroundColor(felt);
        if (Build.VERSION.SDK_INT >= 30) bars30(dark);
        else legacyBars(felt);
    }

    @SuppressWarnings("deprecation")
    private void legacyBars(int felt) {
        getWindow().setStatusBarColor(felt);
    }

    @TargetApi(30)
    @SuppressWarnings("deprecation")
    private void bars30(boolean dark) {
        if (Build.VERSION.SDK_INT < 35) { // 35+ bunları yok sayar; çubuklar zaten şeffaf
            getWindow().setStatusBarColor(0);
            getWindow().setNavigationBarColor(0);
        }
        WindowInsetsController c = getWindow().getInsetsController();
        if (c == null) return;
        // Üst şerit hep yeşil: açık renkli simgeler. Alt zemin açık temada açık renk: koyu simgeler.
        int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        c.setSystemBarsAppearance(dark ? 0 : WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS, light);
    }

    // ---------- geri tuşu ----------

    /** Uygulamada açık bir panel varsa geri tuşu onu kapatır; yoksa sistem uygulamadan çıkar (tahminli geri animasyonuyla) */
    private void syncBack() {
        if (Build.VERSION.SDK_INT >= 33) back33();
    }

    @TargetApi(33)
    private void back33() {
        boolean want = web != null && web.canGoBack();
        if (want == backOn) return;
        if (backCb == null) backCb = (OnBackInvokedCallback) () -> { if (web != null && web.canGoBack()) web.goBack(); };
        OnBackInvokedDispatcher d = getOnBackInvokedDispatcher();
        if (want) d.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, (OnBackInvokedCallback) backCb);
        else d.unregisterOnBackInvokedCallback((OnBackInvokedCallback) backCb);
        backOn = want;
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() { // Android 12 ve öncesi
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    // ---------- sistemden gelenler ----------

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        js("ybNative.theme('" + (night() ? "dark" : "light") + "')");
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        Uri d = i.getData();
        if (d != null) js("ybNative.deepLink(" + JSONObject.quote(d.toString()) + ")");
    }

    private void js(String code) {
        runOnUiThread(() -> { if (web != null) web.evaluateJavascript("window.ybNative && " + code, null); });
    }

    private void scanFail(String code) { js("ybNative.scanFail('" + code + "')"); }

    /** Sayfanın kullanabildiği telefon yetenekleri */
    private class Bridge {
        @JavascriptInterface public void scan(String source) { runOnUiThread(() -> startScan(source)); }
        @JavascriptInterface public void ocr(String dataUrl) { new Thread(() -> ocrImage(dataUrl)).start(); }
        @JavascriptInterface public void bars(String theme) { runOnUiThread(() -> applyBars("dark".equals(theme) ? "dark" : "light")); }
        @JavascriptInterface public String version() { return "1.0.1"; }
        @JavascriptInterface public void ready() { pageReady = true; }
    }

    // ---------- fotoğrafla sayma ----------

    private void startScan(String source) {
        Intent i;
        if ("camera".equals(source)) {
            try {
                File dir = new File(getCacheDir(), "foto");
                //noinspection ResultOfMethodCallIgnored
                dir.mkdirs();
                cameraUri = FileProvider.getUriForFile(this, getPackageName() + ".dosya", new File(dir, "istaka.jpg"));
                i = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                i.putExtra(MediaStore.EXTRA_OUTPUT, cameraUri);
                i.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (Exception e) { scanFail("no_camera"); return; }
        } else {
            cameraUri = null;
            i = new Intent(Intent.ACTION_GET_CONTENT);
            i.setType("image/*");
            i.addCategory(Intent.CATEGORY_OPENABLE);
        }
        try { startActivityForResult(i, REQ_SCAN); }
        catch (ActivityNotFoundException e) { scanFail("no_camera"); }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_FILE) {
            if (fileCb != null) { fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data)); fileCb = null; }
            return;
        }
        if (req != REQ_SCAN) return;
        if (res != RESULT_OK) { scanFail("cancelled"); return; }
        final Uri u = cameraUri != null ? cameraUri : (data != null ? data.getData() : null);
        if (u == null) { scanFail("fail"); return; }
        new Thread(() -> readPhoto(u)).start();
    }

    /** Fotoğrafı yönünü düzelterek en çok 1600 piksele indirir, yazıları okur, görüntüyle birlikte sayfaya yollar */
    private void readPhoto(Uri u) {
        try {
            final Bitmap bm = load(u, 1600);
            recognizer.process(InputImage.fromBitmap(bm, 0))
                    .addOnSuccessListener(t -> {
                        try {
                            JSONObject o = items(t);
                            o.put("w", bm.getWidth());
                            o.put("h", bm.getHeight());
                            o.put("img", "data:image/jpeg;base64," + jpeg(bm));
                            js("ybNative.scanDone(" + JSONObject.quote(o.toString()) + ")");
                        } catch (Exception e) { scanFail("fail"); }
                    })
                    .addOnFailureListener(e -> scanFail("fail"));
        } catch (Exception e) { scanFail("fail"); }
    }

    private void ocrImage(String dataUrl) {
        try {
            byte[] b = Base64.decode(dataUrl.substring(dataUrl.indexOf(',') + 1), Base64.DEFAULT);
            Bitmap bm = BitmapFactory.decodeByteArray(b, 0, b.length);
            if (bm == null) throw new Exception("decode");
            recognizer.process(InputImage.fromBitmap(bm, 0))
                    .addOnSuccessListener(t -> {
                        try { js("ybNative.ocrDone(" + JSONObject.quote(items(t).toString()) + ")"); }
                        catch (Exception e) { js("ybNative.ocrFail('fail')"); }
                    })
                    .addOnFailureListener(e -> js("ybNative.ocrFail('fail')"));
        } catch (Exception e) { js("ybNative.ocrFail('fail')"); }
    }

    private static JSONObject items(Text t) throws Exception {
        JSONArray a = new JSONArray();
        for (Text.TextBlock bl : t.getTextBlocks())
            for (Text.Line ln : bl.getLines())
                for (Text.Element el : ln.getElements()) {
                    Rect r = el.getBoundingBox();
                    if (r == null) continue;
                    JSONObject o = new JSONObject();
                    o.put("t", el.getText());
                    o.put("x", r.left);
                    o.put("y", r.top);
                    o.put("w", r.width());
                    o.put("h", r.height());
                    a.put(o);
                }
        JSONObject o = new JSONObject();
        o.put("items", a);
        return o;
    }

    private Bitmap load(Uri u, int max) throws Exception {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        try (InputStream in = getContentResolver().openInputStream(u)) { BitmapFactory.decodeStream(in, null, o); }
        int sample = 1;
        while (Math.max(o.outWidth, o.outHeight) / (sample * 2) >= max) sample *= 2;
        BitmapFactory.Options o2 = new BitmapFactory.Options();
        o2.inSampleSize = sample;
        Bitmap bm;
        try (InputStream in = getContentResolver().openInputStream(u)) { bm = BitmapFactory.decodeStream(in, null, o2); }
        if (bm == null) throw new Exception("decode");
        int rot = 0;
        try (InputStream in = getContentResolver().openInputStream(u)) {
            if (in != null) {
                int ori = new ExifInterface(in).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
                rot = ori == ExifInterface.ORIENTATION_ROTATE_90 ? 90 : ori == ExifInterface.ORIENTATION_ROTATE_180 ? 180 : ori == ExifInterface.ORIENTATION_ROTATE_270 ? 270 : 0;
            }
        } catch (Exception ignored) { }
        float sc = Math.min(1f, (float) max / Math.max(bm.getWidth(), bm.getHeight()));
        if (sc < 1f || rot != 0) {
            Matrix m = new Matrix();
            m.postScale(sc, sc);
            m.postRotate(rot);
            bm = Bitmap.createBitmap(bm, 0, 0, bm.getWidth(), bm.getHeight(), m, true);
        }
        return bm;
    }

    private static String jpeg(Bitmap bm) {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        bm.compress(Bitmap.CompressFormat.JPEG, 80, b);
        return Base64.encodeToString(b.toByteArray(), Base64.NO_WRAP);
    }

    @Override
    protected void onDestroy() {
        if (recognizer != null) recognizer.close();
        if (web != null) { web.destroy(); web = null; }
        super.onDestroy();
    }
}
