#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <unistd.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
static OSStatus memoryHotKey(EventHandlerCallRef next, EventRef event, void *context);

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
    EventHotKeyRef key;
    RegisterEventHotKey(46, cmdKey | shiftKey, (EventHotKeyID){'LMEM',1}, GetApplicationEventTarget(), 0, &key);
    EventTypeSpec spec={kEventClassKeyboard,kEventHotKeyPressed};
    InstallApplicationEventHandler(memoryHotKey,1,&spec,(__bridge void *)self,NULL);
    [self setStatus:@"正在检查本机服务…"];
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(checkServices)
                                                    userInfo:nil
                                                     repeats:YES];
    [self checkServices];
}

- (void)saveSelection {
    NSRunningApplication *source=NSWorkspace.sharedWorkspace.frontmostApplication;
    NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        NSAlert *a=[NSAlert new]; a.messageText=@"请允许 LocalMind 使用辅助功能"; a.informativeText=@"在系统设置授权后，可读取你主动选中的文字。授权后再按 ⇧⌘M。"; [a runModal]; return;
    }
    AXUIElementRef app=AXUIElementCreateApplication(source.processIdentifier);
    CFTypeRef focused=NULL, selected=NULL, title=NULL;
    AXUIElementCopyAttributeValue(app,kAXFocusedUIElementAttribute,&focused);
    if(focused) AXUIElementCopyAttributeValue((AXUIElementRef)focused,kAXSelectedTextAttribute,&selected);
    AXUIElementCopyAttributeValue(app,kAXFocusedWindowAttribute,&title);
    CFTypeRef windowTitle=NULL;
    if(title) AXUIElementCopyAttributeValue((AXUIElementRef)title,kAXTitleAttribute,&windowTitle);
    NSString *text=selected && CFGetTypeID(selected)==CFStringGetTypeID()? [(__bridge NSString *)selected copy]:@"";
    NSString *window=windowTitle && CFGetTypeID(windowTitle)==CFStringGetTypeID()?[(__bridge NSString *)windowTitle copy]:@"";
    if(focused) CFRelease(focused); if(selected) CFRelease(selected); if(title) CFRelease(title); if(windowTitle) CFRelease(windowTitle); CFRelease(app);
    if (!text.length && NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier==source.processIdentifier) {
        // Wait until the shortcut modifiers are released before issuing Copy.
        NSDate *releaseDeadline=[NSDate dateWithTimeIntervalSinceNow:1.2];
        while ((CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)&(kCGEventFlagMaskShift|kCGEventFlagMaskCommand)) && [releaseDeadline timeIntervalSinceNow]>0) {
            [NSThread sleepForTimeInterval:0.02];
        }
        if (!(CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)&(kCGEventFlagMaskShift|kCGEventFlagMaskCommand))) {
            NSPasteboard *pasteboard=NSPasteboard.generalPasteboard;
            NSMutableArray *backup=[NSMutableArray array];
            for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
                NSPasteboardItem *copy=[NSPasteboardItem new];
                for (NSPasteboardType type in item.types) {NSData *data=[item dataForType:type]; if(data)[copy setData:data forType:type];}
                [backup addObject:copy];
            }
            NSInteger before=pasteboard.changeCount;
            CGEventRef down=CGEventCreateKeyboardEvent(NULL,8,true),up=CGEventCreateKeyboardEvent(NULL,8,false);
            CGEventSetFlags(down,kCGEventFlagMaskCommand);CGEventSetFlags(up,kCGEventFlagMaskCommand);
            CGEventPost(kCGHIDEventTap,down);CGEventPost(kCGHIDEventTap,up);CFRelease(down);CFRelease(up);
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:0.8];
            while(pasteboard.changeCount==before && [deadline timeIntervalSinceNow]>0) [NSThread sleepForTimeInterval:0.02];
            if(pasteboard.changeCount!=before) {
                NSInteger copiedVersion=pasteboard.changeCount;
                if(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier==source.processIdentifier)
                    text=[[pasteboard stringForType:NSPasteboardTypeString] copy]?:@"";
                // Restore only if nobody has copied newer content in the meantime.
                if(pasteboard.changeCount==copiedVersion){[pasteboard clearContents];if(backup.count)[pasteboard writeObjects:backup];}
            }
        }
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert=[NSAlert new]; alert.messageText=@"保存到项目记忆";alert.informativeText=text.length?@"已读取选中文字，请确认原文并补充项目与说明。":@"未读取到可复制的文字。请先选中文字再按 ⇧⌘M；图片中的文字暂不支持，可在此粘贴。";
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,460,240)];
    NSTextField *project=[[NSTextField alloc] initWithFrame:NSMakeRect(0,205,460,28)];project.placeholderString=@"所属项目";
    NSTextField *note=[[NSTextField alloc] initWithFrame:NSMakeRect(0,165,460,28)];note.placeholderString=@"补充说明，例如：客户确认的最终口径";
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,460,150)];scroll.hasVerticalScroller=YES;
    NSTextView *body=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,440,150)];body.font=[NSFont systemFontOfSize:14];body.string=text;scroll.documentView=body;
    [view addSubview:project];[view addSubview:note];[view addSubview:scroll];alert.accessoryView=view;
    [alert addButtonWithTitle:@"保存记忆"];[alert addButtonWithTitle:@"取消"];
    [alert.window makeFirstResponder:text.length?project:body];
    if([alert runModal]!=NSAlertFirstButtonReturn || ![body.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)return;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8787/api/notes"]];request.HTTPMethod=@"POST";[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"text":body.string,@"project":project.stringValue,@"note":note.stringValue,@"app":source.localizedName?:@"",@"window":window} options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),^{NSAlert *done=[NSAlert new];done.messageText=(!error && [(NSHTTPURLResponse *)response statusCode]==201)?@"记忆已保存":@"保存失败，请重试";[done runModal];});}] resume];
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

static OSStatus memoryHotKey(EventHandlerCallRef next, EventRef event, void *context) { [(__bridge LocalMindAppDelegate *)context saveSelection]; return noErr; }
