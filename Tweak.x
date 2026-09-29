#import <UIKit/UIKit.h>

static UILabel *VCAMLabel = nil;

static void VCamInstallOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
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

        if (!window) {
            return;
        }

        [VCAMLabel removeFromSuperview];

        VCAMLabel = [[UILabel alloc]
            initWithFrame:CGRectMake(16, 48, 230, 34)];

        VCAMLabel.text = @"VCam Test Tweak: LOADED";
        VCAMLabel.textAlignment = NSTextAlignmentCenter;
        VCAMLabel.font =
            [UIFont systemFontOfSize:13
                              weight:UIFontWeightSemibold];

        VCAMLabel.textColor = UIColor.whiteColor;

        VCAMLabel.backgroundColor =
            [[UIColor blackColor] colorWithAlphaComponent:0.75];

        VCAMLabel.layer.cornerRadius = 8.0;
        VCAMLabel.clipsToBounds = YES;

        [window addSubview:VCAMLabel];

        NSLog(@"[VCamTestTweak] loaded in %@",
              NSBundle.mainBundle.bundleIdentifier ?: @"<unknown>");
    });
}

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier
         isEqualToString:@"com.tom.VCamTestHost"]) {
        VCamInstallOverlay();
    }
}
