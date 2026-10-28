#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <unistd.h>

@interface LocalMindAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSProgressIndicator *spinner;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) NSTask *ollamaTask;
@property(nonatomic) BOOL didKickstartLocalMind;
@property(nonatomic) BOOL didStartOllama;
@property(nonatomic) NSInteger pollCount;
@end

@implementation LocalMindAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self setStatus:@"正在检查本机服务…"];
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(checkServices)
                                                    userInfo:nil
                                                     repeats:YES];
    [self checkServices];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1120, 780)
                                               styleMask:NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    self.window.title = @"LocalMind 本地记忆";
    self.window.minSize = NSMakeSize(760, 560);
    [self.window center];

    NSView *root = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = root;

    NSView *startup = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1120, 780)];
    startup.translatesAutoresizingMaskIntoConstraints = NO;
    startup.wantsLayer = YES;
    startup.layer.backgroundColor = [NSColor colorWithRed:0.075 green:0.078 blue:0.09 alpha:1].CGColor;
    [root addSubview:startup];
    [NSLayoutConstraint activateConstraints:@[
        [startup.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [startup.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [startup.topAnchor constraintEqualToAnchor:root.topAnchor],
        [startup.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];

    NSTextField *title = [NSTextField labelWithString:@"LocalMind"];
    title.font = [NSFont systemFontOfSize:27 weight:NSFontWeightSemibold];
    title.textColor = [NSColor colorWithRed:0.89 green:0.87 blue:0.96 alpha:1];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [startup addSubview:title];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:13];
    self.statusLabel.textColor = [NSColor colorWithRed:0.67 green:0.67 blue:0.72 alpha:1];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [startup addSubview:self.statusLabel];

    self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeRegular;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.spinner startAnimation:nil];
    [startup addSubview:self.spinner];

    NSButton *retry = [NSButton buttonWithTitle:@"重新检查" target:self action:@selector(checkServices)];
    retry.bezelStyle = NSBezelStyleRounded;
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    [startup addSubview:retry];

    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:startup.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:startup.centerYAnchor constant:-38],
        [self.spinner.centerXAnchor constraintEqualToAnchor:startup.centerXAnchor constant:-95],
        [self.spinner.centerYAnchor constraintEqualToAnchor:startup.centerYAnchor constant:18],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.spinner.trailingAnchor constant:14],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.spinner.centerYAnchor],
        [self.statusLabel.widthAnchor constraintLessThanOrEqualToConstant:420],
        [retry.centerXAnchor constraintEqualToAnchor:startup.centerXAnchor],
        [retry.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:24]
    ]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:root.bounds configuration:configuration];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.hidden = YES;
    [root addSubview:self.webView];
}

- (void)setStatus:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.stringValue = message; });
}

- (void)checkServices {
    self.pollCount += 1;
    [self requestURL:@"http://127.0.0.1:11434/api/tags" completion:^(NSDictionary *json, NSError *error) {
        if (error && !self.didStartOllama) {
            [self startOllama];
        }
        if (!error) {
            [self setStatus:@"Ollama 已启动，正在连接 LocalMind…"];
        } else {
            [self setStatus:@"正在启动本机模型服务 Ollama…"];
        }
        [self checkLocalMind];
    }];
}

- (void)checkLocalMind {
    [self requestURL:@"http://127.0.0.1:8787/api/status" completion:^(NSDictionary *json, NSError *error) {
        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.webView.hidden) {
                    self.webView.hidden = NO;
                    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8787/"]]];
                }
                [self.spinner stopAnimation:nil];
                self.statusLabel.superview.hidden = YES;
            });
            [self.pollTimer invalidate];
        } else if (!self.didKickstartLocalMind) {
            self.didKickstartLocalMind = YES;
            [self kickstartLocalMind];
        }
        if (self.pollCount > 18 && error) {
            [self setStatus:@"LocalMind 尚未响应，请确认安装脚本已运行后点击重新检查。"];
        }
    }];
}

- (void)startOllama {
    self.didStartOllama = YES;
    NSString *path = @"/opt/homebrew/bin/ollama";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) path = @"/usr/local/bin/ollama";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        [self setStatus:@"找不到 Ollama。请先安装 Ollama，然后重新检查。"];
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = @[@"serve"];
    task.environment = @{ @"HOME": NSHomeDirectory(), @"PATH": @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" };
    task.standardOutput = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
    task.standardError = task.standardOutput;
    self.ollamaTask = task;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.didStartOllama = NO;
        [self setStatus:[NSString stringWithFormat:@"启动 Ollama 失败：%@", error.localizedDescription]];
    }
}

- (void)kickstartLocalMind {
    NSString *uid = [NSString stringWithFormat:@"%d", getuid()];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[@"kickstart", @"-k", [NSString stringWithFormat:@"gui/%@/com.localmind.agent", uid]];
    [task launchAndReturnError:nil];
}

- (void)requestURL:(NSString *)url completion:(void (^)(NSDictionary *, NSError *))completion {
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = nil;
        if (data.length) json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        completion(json, error);
    }];
    [task resume];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        LocalMindAppDelegate *delegate = [[LocalMindAppDelegate alloc] init];
        app.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}
