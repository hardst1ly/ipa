// Расписание уроков — обёртка для iOS.
// Полноэкранный WKWebView, который показывает www/ из бандла приложения
// через собственную схему app://localhost (постоянный origin => localStorage сохраняется).
// Собирается из Linux: zig cc -target aarch64-ios + iPhoneOS SDK (см. standalone/build.sh).

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// ---------- app:// — отдаёт файлы из Payload/App.app/www ----------

@interface AppSchemeHandler : NSObject <WKURLSchemeHandler>
@end

@implementation AppSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
  NSURL *url = task.request.URL;
  NSString *path = url.path;
  if (path.length == 0 || [path isEqualToString:@"/"]) {
    path = @"/index.html";
  }
  NSString *base = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
  NSString *file = [[base stringByAppendingPathComponent:path] stringByStandardizingPath];
  NSData *data = nil;
  if ([file hasPrefix:base]) {
    data = [NSData dataWithContentsOfFile:file];
  }
  if (data == nil) {
    [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorFileDoesNotExist
                                           userInfo:nil]];
    return;
  }

  NSDictionary<NSString *, NSString *> *types = @{
    @"html" : @"text/html; charset=utf-8",
    @"js" : @"application/javascript; charset=utf-8",
    @"css" : @"text/css; charset=utf-8",
    @"json" : @"application/json; charset=utf-8",
    @"png" : @"image/png",
    @"svg" : @"image/svg+xml",
  };
  NSString *mime = types[file.pathExtension.lowercaseString] ?: @"application/octet-stream";
  NSDictionary *headers = @{
    @"Content-Type" : mime,
    @"Content-Length" : [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
    @"Cache-Control" : @"no-cache",
  };
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url
                                                            statusCode:200
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:headers];
  [task didReceiveResponse:response];
  [task didReceiveData:data];
  [task didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
}

@end

// ---------- Экран с WebView ----------

@interface ViewController : UIViewController
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) AppSchemeHandler *schemeHandler;
@end

@implementation ViewController

- (void)loadView {
  WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
  self.schemeHandler = [[AppSchemeHandler alloc] init];
  [config setURLSchemeHandler:self.schemeHandler forURLScheme:@"app"];
  config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

  WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
  // Отступы под «чёлку» и полоску «домой» делает CSS через env(safe-area-inset-*)
  web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  web.scrollView.bounces = YES;
  web.allowsBackForwardNavigationGestures = NO;
  web.opaque = NO;
  web.backgroundColor = [UIColor systemGroupedBackgroundColor];
  web.scrollView.backgroundColor = [UIColor systemGroupedBackgroundColor];
  self.webView = web;
  self.view = web;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NSURL *start = [NSURL URLWithString:@"app://localhost/index.html"];
  [self.webView loadRequest:[NSURLRequest requestWithURL:start]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleDefault;
}

@end

// ---------- Приложение ----------

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  self.window.backgroundColor = [UIColor systemGroupedBackgroundColor];
  self.window.rootViewController = [[ViewController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
