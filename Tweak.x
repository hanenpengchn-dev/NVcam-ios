#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>
#include <time.h>

#pragma mark - Globals

static UILabel *VCAMLabel = nil;
static UIButton *VCAMToggleButton = nil;
static UIButton *VCAMLogButton = nil;
static UIView *VCamLogPanel = nil;
static UITextView *VCamLogView = nil;
static BOOL VCamIsOn = NO;
static NSMutableArray<NSString *> *VCamLogLines = nil;
static NSMapTable *VCamProxyMap = nil;
static NSMapTable *VCamPreviewMap = nil;
static NSTimer *VCamOverlayTimer = nil;
static unsigned long VCamOverlayFrame = 0;
static unsigned long VCamFakeFrames = 0;

static void VCamTryAttach(int attemptsLeft);
static void VCamApplyState(void);
static void VCamStartOverlayTimerIfNeeded(void);

#pragma mark - Logging

static void VCamRefreshLogUI(void) {
    if (!VCamLogView) {
        return;
    }
    NSArray<NSString *> *lines = nil;
    @synchronized (VCamLogLines) {
        lines = [VCamLogLines copy];
    }
    NSInteger start = (NSInteger)lines.count - 22;
    if (start < 0) {
        start = 0;
    }
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = start; i < (NSInteger)lines.count; i++) {
        [text appendString:lines[(NSUInteger)i]];
        [text appendString:@"\n"];
    }
    VCamLogView.text = text;
    if (text.length > 0) {
        [VCamLogView scrollRangeToVisible:NSMakeRange(text.length - 1, 1)];
    }
}

static void VCamLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    char tbuf[16];
    strftime(tbuf, sizeof(tbuf), "%H:%M:%S", &tmv);

    NSString *line = [NSString stringWithFormat:@"%s  %@", tbuf, msg];
    if (!VCamLogLines) {
        VCamLogLines = [NSMutableArray array];
    }
    @synchronized (VCamLogLines) {
        [VCamLogLines addObject:line];
        if (VCamLogLines.count > 100) {
            [VCamLogLines removeObjectsInRange:NSMakeRange(0, VCamLogLines.count - 100)];
        }
    }
    NSLog(@"[VCamTestTweak] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        VCamRefreshLogUI();
    });
}

#pragma mark - Test pattern drawing

static void VCamDrawText(CGContextRef ctx, NSString *text, CGFloat x, CGFloat y, CGFloat fontSize) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica-Bold"), fontSize, NULL);
    CGColorRef white = CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0);
    NSDictionary *attrs = @{
        (__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)white
    };
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)as);
    CGContextSetTextPosition(ctx, x, y);
    CTLineDraw(line, ctx);
    CFRelease(line);
    CGColorRelease(white);
    CFRelease(font);
}

static void VCamDrawPattern(CGContextRef ctx, CGSize size, unsigned long frameNo) {
    CGFloat w = size.width;
    CGFloat h = size.height;

    UIColor *colors[4] = {
        [UIColor colorWithRed:0.12 green:0.42 blue:0.92 alpha:1.0],
        [UIColor colorWithRed:0.95 green:0.72 blue:0.10 alpha:1.0],
        [UIColor colorWithRed:0.18 green:0.72 blue:0.34 alpha:1.0],
        [UIColor colorWithRed:0.82 green:0.20 blue:0.55 alpha:1.0]
    };
    for (int i = 0; i < 4; i++) {
        CGContextSetFillColorWithColor(ctx, colors[i].CGColor);
        CGContextFillRect(ctx, CGRectMake(w * (CGFloat)i / 4.0, 0, w / 4.0, h));
    }

    // moving marker
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGFloat cx = (CGFloat)((frameNo * 13) % (unsigned long)w);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - 24.0, h - 140.0, 48.0, 48.0));

    // dark top strip for text
    CGContextSetFillColorWithColor(ctx, [[UIColor blackColor] colorWithAlphaComponent:0.55].CGColor);
    CGContextFillRect(ctx, CGRectMake(0, h - 150.0, w, 150.0));

    NSString *line1 = @"VIRTUAL CAMERA (VCam Test)";
    NSString *line2 = [NSString stringWithFormat:@"frame #%lu", frameNo];
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    char tbuf[32];
    strftime(tbuf, sizeof(tbuf), "%H:%M:%S", &tmv);
    NSString *line3 = [NSString stringWithFormat:@"%s", tbuf];
    NSString *line4 = NSBundle.mainBundle.bundleIdentifier ?: @"(unknown app)";

    VCamDrawText(ctx, line1, 24.0, h - 62.0, 34.0);
    VCamDrawText(ctx, line2, 24.0, h - 100.0, 24.0);
    VCamDrawText(ctx, line3, 300.0, h - 100.0, 24.0);
    VCamDrawText(ctx, line4, 24.0, h - 132.0, 18.0);
}

#pragma mark - Frame factory

static CMSampleBufferRef VCamCreateFakeFrame(unsigned long frameNo) CF_RETURNS_RETAINED;
static CMSampleBufferRef VCamCreateFakeFrame(unsigned long frameNo) {
    size_t w = 1280, h = 720;
    NSDictionary *attrs = @{
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs, &pb);
    if (r != kCVReturnSuccess || !pb) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pb, 0);
    void *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, w, h, 8, stride, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (ctx) {
        VCamDrawPattern(ctx, CGSizeMake((CGFloat)w, (CGFloat)h), frameNo);
        CGContextRelease(ctx);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);

    CMVideoFormatDescriptionRef fmt = NULL;
    OSStatus s = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &fmt);
    if (s != noErr || !fmt) {
        CVPixelBufferRelease(pb);
        return NULL;
    }

    CMSampleTimingInfo timing;
    timing.duration = CMTimeMake(1, 30);
    timing.presentationTimeStamp = CMTimeMake((int64_t)frameNo, 30);
    timing.decodeTimeStamp = kCMTimeInvalid;

    CMSampleBufferRef sb = NULL;
    s = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pb, fmt, &timing, &sb);
    CFRelease(fmt);
    CVPixelBufferRelease(pb);
    if (s != noErr) {
        return NULL;
    }
    return sb;
}

static CGImageRef VCamCreatePatternImage(unsigned long frameNo) CF_RETURNS_RETAINED;
static CGImageRef VCamCreatePatternImage(unsigned long frameNo) {
    size_t w = 640, h = 360;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        return NULL;
    }
    VCamDrawPattern(ctx, CGSizeMake((CGFloat)w, (CGFloat)h), frameNo);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

#pragma mark - Preview layer overlay

static void VCamStartOverlayTimerIfNeeded(void) {
    if (VCamOverlayTimer) {
        return;
    }
    VCamOverlayTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        if (!VCamPreviewMap || VCamPreviewMap.count == 0) {
            [t invalidate];
            VCamOverlayTimer = nil;
            return;
        }
        VCamOverlayFrame++;
        NSArray *keys = [[VCamPreviewMap keyEnumerator] allObjects];
        for (CALayer *layer in keys) {
            id val = [VCamPreviewMap objectForKey:layer];
            if (!layer) {
                continue;
            }
            if (val == (id)[NSNull null]) {
                CALayer *host = layer.superlayer;
                if (!host) {
                    continue;
                }
                CALayer *ov = [CALayer layer];
                ov.name = @"VCamOverlay";
                ov.zPosition = 10000;
                ov.contentsGravity = kCAGravityResize;
                [host insertSublayer:ov above:layer];
                [VCamPreviewMap setObject:ov forKey:layer];
                val = ov;
                VCamLog(@"已给预览层叠加画面控制");
            }
            CALayer *ov = val;
            if (ov == (id)[NSNull null]) {
                continue;
            }
            ov.frame = layer.frame;
            ov.hidden = !VCamIsOn;
            if (VCamIsOn) {
                CGImageRef img = VCamCreatePatternImage(VCamOverlayFrame);
                if (img) {
                    ov.contents = (__bridge id)img;
                    CGImageRelease(img);
                }
            }
        }
    }];
}

static void VCamTrackPreviewLayer(CALayer *layer) {
    if (!layer) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!VCamPreviewMap) {
            VCamPreviewMap = [NSMapTable weakToStrongObjectsMapTable];
        }
        if ([VCamPreviewMap objectForKey:layer]) {
            return;
        }
        [VCamPreviewMap setObject:[NSNull null] forKey:layer];
        VCamStartOverlayTimerIfNeeded();
    });
}

#pragma mark - Sample buffer proxy

@interface VCamSampleBufferProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCamSampleBufferProxy

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    return self.originalDelegate;
}

- (void)captureOutput:(AVCaptureOutput *)output
        didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection {
    id orig = self.originalDelegate;
    BOOL origHandles = [orig respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
    if (VCamIsOn) {
        @try {
            VCamFakeFrames++;
            CMSampleBufferRef fake = VCamCreateFakeFrame(VCamFakeFrames);
            if (fake) {
                if (origHandles) {
                    [orig captureOutput:output didOutputSampleBuffer:fake fromConnection:connection];
                }
                CFRelease(fake);
                if (VCamFakeFrames % 90 == 0) {
                    VCamLog(@"虚拟画面已替换 %lu 帧", VCamFakeFrames);
                }
                return;
            }
        } @catch (NSException *e) {
            VCamLog(@"帧替换异常: %@", e.reason ?: @"?");
        }
    }
    if (origHandles) {
        [orig captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
        didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection {
    id orig = self.originalDelegate;
    if ([orig respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        [orig captureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

@end

#pragma mark - UI

@interface VCamDragTarget : NSObject
@end

@implementation VCamDragTarget
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    if (!view || !view.superview) {
        return;
    }
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x,
                              view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];

    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled) {
        UIView *superview = view.superview;
        CGFloat halfW = view.bounds.size.width / 2.0;
        CGFloat halfH = view.bounds.size.height / 2.0;
        CGFloat x = view.center.x;
        CGFloat y = view.center.y;
        x = MAX(halfW + 6.0, MIN(x, superview.bounds.size.width - halfW - 6.0));
        y = MAX(halfH + 40.0, MIN(y, superview.bounds.size.height - halfH - 40.0));
        [UIView animateWithDuration:0.15 animations:^{
            view.center = CGPointMake(x, y);
        }];
    }
}
@end

static VCamDragTarget *VCamDrag = nil;

static void VCamApplyState(void) {
    if (VCAMLabel) {
        VCAMLabel.hidden = !VCamIsOn;
    }
    if (VCAMToggleButton) {
        VCAMToggleButton.backgroundColor = VCamIsOn
            ? [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:0.90]
            : [[UIColor blackColor] colorWithAlphaComponent:0.55];
        [VCAMToggleButton setTitle:(VCamIsOn ? @"ON" : @"OFF")
                          forState:UIControlStateNormal];
        [VCAMToggleButton setTitleColor:UIColor.whiteColor
                               forState:UIControlStateNormal];
    }
}

static UIWindow *VCamFindWindow(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                    if (!candidate.hidden &&
                        candidate.alpha > 0.0 &&
                        candidate.windowLevel == UIWindowLevelNormal) {
                        window = candidate;
                        break;
                    }
                }
            }
            if (window) {
                break;
            }
        }
    } else {
        window = UIApplication.sharedApplication.keyWindow;
    }
    return window;
}

static void VCamInstallUI(UIWindow *window) {
    if (!window) {
        return;
    }

    [VCAMLabel removeFromSuperview];
    [VCAMToggleButton removeFromSuperview];
    [VCAMLogButton removeFromSuperview];
    [VCamLogPanel removeFromSuperview];

    VCAMLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(16, 48, 230, 34)];
    VCAMLabel.text = @"VCam Test Tweak: LOADED";
    VCAMLabel.textAlignment = NSTextAlignmentCenter;
    VCAMLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    VCAMLabel.textColor = UIColor.whiteColor;
    VCAMLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    VCAMLabel.layer.cornerRadius = 8.0;
    VCAMLabel.clipsToBounds = YES;
    [window addSubview:VCAMLabel];

    VCAMToggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat side = 56.0;
    CGFloat startX = window.bounds.size.width - side - 14.0;
    if (startX < 14.0) {
        startX = 14.0;
    }
    VCAMToggleButton.frame = CGRectMake(startX, 120.0, side, side);
    VCAMToggleButton.layer.cornerRadius = side / 2.0;
    VCAMToggleButton.clipsToBounds = YES;
    VCAMToggleButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [VCAMToggleButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
        VCamIsOn = !VCamIsOn;
        VCamApplyState();
        VCamLog(@"虚拟相机: %@", VCamIsOn ? @"ON" : @"OFF");
    }] forControlEvents:UIControlEventTouchUpInside];

    if (!VCamDrag) {
        VCamDrag = [[VCamDragTarget alloc] init];
    }
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:VCamDrag
                                                action:@selector(handlePan:)];
    [VCAMToggleButton addGestureRecognizer:pan];
    [window addSubview:VCAMToggleButton];

    VCAMLogButton = [UIButton buttonWithType:UIButtonTypeCustom];
    VCAMLogButton.frame = CGRectMake(startX, 120.0 + side + 10.0, side, 30.0);
    VCAMLogButton.layer.cornerRadius = 15.0;
    VCAMLogButton.clipsToBounds = YES;
    VCAMLogButton.backgroundColor = [[UIColor colorWithRed:0.10 green:0.45 blue:0.90 alpha:0.85] colorWithAlphaComponent:0.9];
    VCAMLogButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [VCAMLogButton setTitle:@"LOG" forState:UIControlStateNormal];
    [VCAMLogButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [VCAMLogButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
        if (!VCamLogPanel) {
            return;
        }
        VCamLogPanel.hidden = !VCamLogPanel.hidden;
        if (!VCamLogPanel.hidden) {
            VCamRefreshLogUI();
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:VCAMLogButton];

    VCamLogPanel = [[UIView alloc] initWithFrame:CGRectMake(16, 92, 320, 210)];
    VCamLogPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.80];
    VCamLogPanel.layer.cornerRadius = 10.0;
    VCamLogPanel.clipsToBounds = YES;
    VCamLogPanel.hidden = YES;

    VCamLogView = [[UITextView alloc] initWithFrame:CGRectMake(6, 6, 308, 198)];
    VCamLogView.backgroundColor = [UIColor clearColor];
    VCamLogView.textColor = [UIColor whiteColor];
    VCamLogView.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    VCamLogView.editable = NO;
    VCamLogView.scrollEnabled = YES;
    [VCamLogPanel addSubview:VCamLogView];
    [window addSubview:VCamLogPanel];

    VCamApplyState();

    VCamLog(@"attached (virtual-camera v2) in %@",
            NSBundle.mainBundle.bundleIdentifier ?: @"<unknown>");
}

static void VCamTryAttach(int attemptsLeft) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = VCamFindWindow();
        if (!window) {
            if (attemptsLeft > 1) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    VCamTryAttach(attemptsLeft - 1);
                });
            } else {
                VCamLog(@"window not found after retries");
            }
            return;
        }
        VCamInstallUI(window);
    });
}

#pragma mark - Whitelist

static NSString *VCamWhitelistContents(void) {
    NSArray<NSString *> *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/vcam_whitelist.txt",
        @"/var/mobile/Library/Preferences/vcam_whitelist.txt"
    ];
    for (NSString *p in paths) {
        NSStringEncoding enc = 0;
        NSString *content = [NSString stringWithContentsOfFile:p
                                                     usedEncoding:&enc
                                                            error:NULL];
        if (content) {
            return content;
        }
    }
    return nil;
}

static BOOL VCamIsWhitelisted(NSString *bundleID) {
    NSString *content = VCamWhitelistContents();
    if (!content) {
        return YES;
    }
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSArray<NSString *> *lines =
        [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0 || [line hasPrefix:@"#"]) {
            continue;
        }
        [ids addObject:[line lowercaseString]];
    }
    if (ids.count == 0) {
        return YES;
    }
    return [ids containsObject:[bundleID lowercaseString]];
}

static BOOL VCamShouldAttach(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID) {
        return NO;
    }
    if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) {
        return NO;
    }
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        return NO;
    }
    if (!VCamIsWhitelisted(bundleID)) {
        NSLog(@"[VCamTestTweak] %@ skipped (not in whitelist)", bundleID);
        return NO;
    }
    return YES;
}

#pragma mark - Hooks: probe

%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType {
    AVCaptureDevice *d = %orig;
    VCamLog(@"设备: defaultDevice(%@) -> %@", mediaType, d.localizedName ?: @"nil");
    return d;
}

+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType {
    NSArray *arr = %orig;
    VCamLog(@"设备: devices(%@) -> %lu 个", mediaType, (unsigned long)arr.count);
    return arr;
}

+ (AVCaptureDevice *)deviceWithUniqueID:(NSString *)deviceUniqueID {
    AVCaptureDevice *d = %orig;
    VCamLog(@"设备: deviceWithUniqueID(%@)", deviceUniqueID);
    return d;
}

- (BOOL)lockForConfiguration:(NSError **)outError {
    BOOL r = %orig;
    VCamLog(@"设备: lockForConfiguration -> %d", r);
    return r;
}

%end

%hook AVCaptureDeviceInput

+ (AVCaptureDeviceInput *)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    AVCaptureDeviceInput *input = %orig;
    VCamLog(@"输入: deviceInput(%@)", device.localizedName ?: @"?");
    return input;
}

%end

%hook AVCaptureSession

- (void)beginConfiguration {
    VCamLog(@"会话: beginConfiguration");
    %orig;
}

- (void)commitConfiguration {
    VCamLog(@"会话: commitConfiguration");
    %orig;
}

- (void)addInput:(AVCaptureInput *)input {
    VCamLog(@"会话: addInput(%@)", NSStringFromClass([input class]));
    %orig;
}

- (void)addOutput:(AVCaptureOutput *)output {
    VCamLog(@"会话: addOutput(%@)", NSStringFromClass([output class]));
    %orig;
}

- (void)startRunning {
    VCamLog(@"会话: startRunning");
    %orig;
}

- (void)stopRunning {
    VCamLog(@"会话: stopRunning");
    %orig;
}

%end

#pragma mark - Hooks: interception

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate
                          queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (sampleBufferDelegate && sampleBufferCallbackQueue &&
        ![(id)sampleBufferDelegate isKindOfClass:[VCamSampleBufferProxy class]]) {
        if (!VCamProxyMap) {
            VCamProxyMap = [NSMapTable weakToStrongObjectsMapTable];
        }
        VCamSampleBufferProxy *proxy = [VCamProxyMap objectForKey:self];
        if (!proxy) {
            proxy = [[VCamSampleBufferProxy alloc] init];
            [VCamProxyMap setObject:proxy forKey:self];
        }
        proxy.originalDelegate = sampleBufferDelegate;
        VCamLog(@"视频输出: 已接管 delegate (%@) settings=%@",
                NSStringFromClass([sampleBufferDelegate class]),
                self.videoSettings);
        %orig(proxy, sampleBufferCallbackQueue);
    } else {
        %orig(sampleBufferDelegate, sampleBufferCallbackQueue);
    }
}

%end

%hook AVCaptureMetadataOutput

- (void)setMetadataObjectsDelegate:(id<AVCaptureMetadataOutputObjectsDelegate>)objectsDelegate
                             queue:(dispatch_queue_t)objectsCallbackQueue {
    VCamLog(@"元数据输出: setMetadataObjectsDelegate");
    %orig;
}

%end

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    VCamLog(@"拍照输出: capturePhoto");
    %orig;
}

%end

%hook AVCaptureVideoPreviewLayer

+ (AVCaptureVideoPreviewLayer *)layerWithSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = %orig;
    VCamLog(@"预览层: layerWithSession");
    VCamTrackPreviewLayer(layer);
    return layer;
}

+ (AVCaptureVideoPreviewLayer *)layerWithSessionWithNoConnection:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = %orig;
    VCamLog(@"预览层: layerWithSessionWithNoConnection");
    VCamTrackPreviewLayer(layer);
    return layer;
}

- (void)setSession:(AVCaptureSession *)session {
    VCamLog(@"预览层: setSession");
    %orig;
    VCamTrackPreviewLayer(self);
}

%end

#pragma mark - Entry

%ctor {
    if (VCamShouldAttach()) {
        VCamTryAttach(20);
    }
}
