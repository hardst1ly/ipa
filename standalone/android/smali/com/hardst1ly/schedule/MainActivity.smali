.class public Lcom/hardst1ly/schedule/MainActivity;
.super Landroid/app/Activity;
.source "MainActivity.java"

# Минимальная обёртка: полноэкранный WebView, который показывает www/ из assets.
# Эквивалент на Java:
#
#   public class MainActivity extends Activity {
#       private WebView web;
#       protected void onCreate(Bundle state) {
#           super.onCreate(state);
#           web = new WebView(this);
#           WebSettings s = web.getSettings();
#           s.setJavaScriptEnabled(true);
#           s.setDomStorageEnabled(true);      // localStorage — хранение расписания
#           s.setAllowFileAccess(true);        // file:///android_asset/
#           s.setDatabaseEnabled(true);
#           s.setTextZoom(100);
#           web.setWebViewClient(new WebViewClient());
#           web.setBackgroundColor(0);
#           setContentView(web);
#           web.loadUrl("file:///android_asset/index.html");
#       }
#       public void onBackPressed() {
#           if (web.canGoBack()) web.goBack(); else super.onBackPressed();
#       }
#   }

.field private web:Landroid/webkit/WebView;


.method public constructor <init>()V
    .registers 1

    invoke-direct {p0}, Landroid/app/Activity;-><init>()V

    return-void
.end method


.method protected onCreate(Landroid/os/Bundle;)V
    .registers 5

    invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V

    new-instance v0, Landroid/webkit/WebView;
    invoke-direct {v0, p0}, Landroid/webkit/WebView;-><init>(Landroid/content/Context;)V
    iput-object v0, p0, Lcom/hardst1ly/schedule/MainActivity;->web:Landroid/webkit/WebView;

    invoke-virtual {v0}, Landroid/webkit/WebView;->getSettings()Landroid/webkit/WebSettings;
    move-result-object v1

    const/4 v2, 0x1
    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setJavaScriptEnabled(Z)V
    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setDomStorageEnabled(Z)V
    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setAllowFileAccess(Z)V
    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setDatabaseEnabled(Z)V

    const/16 v2, 0x64
    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setTextZoom(I)V

    new-instance v1, Landroid/webkit/WebViewClient;
    invoke-direct {v1}, Landroid/webkit/WebViewClient;-><init>()V
    invoke-virtual {v0, v1}, Landroid/webkit/WebView;->setWebViewClient(Landroid/webkit/WebViewClient;)V

    const/4 v2, 0x0
    invoke-virtual {v0, v2}, Landroid/webkit/WebView;->setBackgroundColor(I)V

    invoke-virtual {p0, v0}, Lcom/hardst1ly/schedule/MainActivity;->setContentView(Landroid/view/View;)V

    const-string v1, "file:///android_asset/index.html"
    invoke-virtual {v0, v1}, Landroid/webkit/WebView;->loadUrl(Ljava/lang/String;)V

    return-void
.end method


.method public onBackPressed()V
    .registers 3

    iget-object v0, p0, Lcom/hardst1ly/schedule/MainActivity;->web:Landroid/webkit/WebView;
    if-eqz v0, :cond_exit

    invoke-virtual {v0}, Landroid/webkit/WebView;->canGoBack()Z
    move-result v1
    if-eqz v1, :cond_exit

    invoke-virtual {v0}, Landroid/webkit/WebView;->goBack()V
    return-void

    :cond_exit
    invoke-super {p0}, Landroid/app/Activity;->onBackPressed()V
    return-void
.end method
