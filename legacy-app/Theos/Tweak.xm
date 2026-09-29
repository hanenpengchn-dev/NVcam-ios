#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

%hook AVCaptureSession
- (BOOL)startRunning { NSLog(@"[NVcam] AVCaptureSession::startRunning"); return %orig; }
- (void)stopRunning { NSLog(@"[NVcam] AVCaptureSession::stopRunning"); %orig; }
%end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue { NSLog(@"[NVcam] setSampleBufferDelegate:queue:"); %orig; }
%end

%hook AVCaptureDevice
+ (nullable AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType { AVCaptureDevice *device = %orig; if (mediaType == AVMediaTypeVideo) NSLog(@"[NVcam] defaultDeviceWithMediaType:AVMediaTypeVideo -> %@", device.localizedName); return device; }
+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType { NSArray *devices = %orig; if (mediaType == AVMediaTypeVideo) NSLog(@"[NVcam] devicesWithMediaType:AVMediaTypeVideo -> %lu devices", (unsigned long)devices.count); return devices; }
%end

%ctor { NSLog(@"[NVcam] =========================================="); NSLog(@"[NVcam] NVcam Virtual Camera Tweak Loaded"); NSLog(@"[NVcam] Hooking AVFoundation for camera interception"); NSLog(@"[NVcam] =========================================="); }
