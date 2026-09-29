#import <UIKit/UIKit.h>

static UILabel *VCAMLabel = nil;
static UIButton *VCAMToggleButton = nil;
static BOOL VCamIsOn = NO;
static void VCamTryAttach(int attemptsLeft);
static void VCamApplyState(void);

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
        NSLog(@"[VCamTestTweak] toggle state: %d", VCamIsOn);
    }] forControlEvents:UIControlEventTouchUpInside];

    if (!VCamDrag) {
        VCamDrag = [[VCamDragTarget alloc] init];
    }
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:VCamDrag
                                                action:@selector(handlePan:)];
    [VCAMToggleButton addGestureRecognizer:pan];

    [window addSubview:VCAMToggleButton];

    VCamApplyState();

    NSLog(@"[VCamTestTweak] attached in %@",
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
                NSLog(@"[VCamTestTweak] window not found after retries");
            }
            return;
        }
        VCamInstallUI(window);
    });
}

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier
         isEqualToString:@"com.tom.VCamTestHost"]) {
        VCamTryAttach(20);
    }
}
