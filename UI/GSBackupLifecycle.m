#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "GSUploadMonitor.h"
#import "GSBatchImport.h"
#import "GSNativeRouting.h"
#import "GSPhotosIntegration.h"
#import "../Shared/GSLocalization.h"

static NSString * const GSBackupDimmingPreference = @"GSBackupDimmingEnabled";
static const NSTimeInterval GSDimInactivityInterval = 30.0;

static BOOL GSGunshotAcquiredIdleTimer;
static BOOL GSScreenDimmed;
static CGFloat GSOriginalBrightness = -1.0f;
static NSTimer *GSIdleDimTimer;
static UIView *GSDimOverlayView;
static UILabel *GSDimOverlayLabel;

static void GSWakeScreen(BOOL animated);
static void GSResetIdleDimTimer(void);
static void GSDimScreen(void);
static void GSBackupLifecycleDidReceiveTouch(void);

@interface GSDimOverlayViewClass : UIView
@end

@implementation GSDimOverlayViewClass
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
 GSBackupLifecycleDidReceiveTouch();
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
 if (self.hidden || self.alpha < 0.01f) return nil;
 return self;
}
@end

BOOL GSBackupDimmingEnabled(void) {
 id val = [NSUserDefaults.standardUserDefaults objectForKey:GSBackupDimmingPreference];
 return val == nil ? YES : [val boolValue];
}

void GSSetBackupDimming(BOOL enabled) {
 [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GSBackupDimmingPreference];
 if (!enabled) {
  GSWakeScreen(YES);
 } else {
  GSResetIdleDimTimer();
 }
}

BOOL GSScreenDimmedSnapshot(void) {
 return GSScreenDimmed;
}

CGFloat GSScreenOriginalBrightnessSnapshot(void) {
 return GSOriginalBrightness;
}

UIView *GSDimOverlayViewSnapshot(void) {
 return GSDimOverlayView;
}

static BOOL GSSampleHostActive(void) {
 BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
 for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
  if (![scene isKindOfClass:UIWindowScene.class]) continue;
  if (scene.activationState == UISceneActivationStateForegroundActive) return YES;
  if (scene.activationState == UISceneActivationStateForegroundInactive || scene.activationState == UISceneActivationStateBackground) return NO;
 }
 return active;
}

static void GSWakeScreen(BOOL animated) {
 NSCAssert(NSThread.isMainThread, @"Screen wake must run on main");
 [GSIdleDimTimer invalidate];
 GSIdleDimTimer = nil;
 if (GSScreenDimmed) {
  GSScreenDimmed = NO;
  CGFloat targetBrightness = GSOriginalBrightness >= 0.0f ? GSOriginalBrightness : UIScreen.mainScreen.brightness;
  GSOriginalBrightness = -1.0f;
  UIScreen.mainScreen.brightness = targetBrightness;
  if (animated && GSDimOverlayView) {
   [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
    GSDimOverlayView.alpha = 0.0f;
   } completion:^(BOOL finished) {
    if (!GSScreenDimmed) GSDimOverlayView.hidden = YES;
   }];
  } else if (GSDimOverlayView) {
   GSDimOverlayView.alpha = 0.0f;
   GSDimOverlayView.hidden = YES;
  }
 }
}

static void GSDimScreen(void) {
 NSCAssert(NSThread.isMainThread, @"Screen dim must run on main");
 BOOL active = GSSampleHostActive();
 BOOL foreground = GSUploadHostForeground();
 BOOL queueActive = GSUploadQueueActive();
 BOOL batchActive = [GSBatchImportSnapshot()[@"active"] boolValue];
 BOOL shouldKeepAwake = active && foreground && (queueActive || batchActive);
 if (!shouldKeepAwake || !GSBackupDimmingEnabled() || GSScreenDimmed) return;

 UIWindow *targetWindow = nil;
 for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
  if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
  for (UIWindow *w in ((UIWindowScene *)scene).windows) {
   if (w.isKeyWindow) { targetWindow = w; break; }
  }
  if (targetWindow) break;
 }
 if (!targetWindow) {
  for (UIWindow *w in UIApplication.sharedApplication.windows) {
   if (w.isKeyWindow) { targetWindow = w; break; }
  }
 }
 if (!targetWindow) targetWindow = UIApplication.sharedApplication.windows.firstObject;
 if (!targetWindow) return;

 if (!GSDimOverlayView) {
  GSDimOverlayView = [[GSDimOverlayViewClass alloc] initWithFrame:targetWindow.bounds];
  GSDimOverlayView.backgroundColor = UIColor.blackColor;
  GSDimOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  GSDimOverlayLabel = [UILabel new];
  GSDimOverlayLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.3f];
  GSDimOverlayLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
  GSDimOverlayLabel.textAlignment = NSTextAlignmentCenter;
  GSDimOverlayLabel.numberOfLines = 0;
  GSDimOverlayLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [GSDimOverlayView addSubview:GSDimOverlayLabel];
  [NSLayoutConstraint activateConstraints:@[
   [GSDimOverlayLabel.centerXAnchor constraintEqualToAnchor:GSDimOverlayView.centerXAnchor],
   [GSDimOverlayLabel.bottomAnchor constraintEqualToAnchor:GSDimOverlayView.safeAreaLayoutGuide.bottomAnchor constant:-40.0],
   [GSDimOverlayLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:GSDimOverlayView.leadingAnchor constant:20.0],
   [GSDimOverlayLabel.trailingAnchor constraintLessThanOrEqualToAnchor:GSDimOverlayView.trailingAnchor constant:-20.0]
  ]];
 }

 GSDimOverlayLabel.text = GSL(@"Backing up · Tap anywhere to wake");
 GSDimOverlayView.frame = targetWindow.bounds;
 if (GSDimOverlayView.superview != targetWindow) {
  [targetWindow addSubview:GSDimOverlayView];
 }
 [targetWindow bringSubviewToFront:GSDimOverlayView];

 if (GSOriginalBrightness < 0.0f) {
  GSOriginalBrightness = UIScreen.mainScreen.brightness;
 }

 GSScreenDimmed = YES;
 GSDimOverlayView.hidden = NO;
 GSDimOverlayView.alpha = 0.0f;
 [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
  GSDimOverlayView.alpha = 1.0f;
  UIScreen.mainScreen.brightness = 0.0f;
 } completion:^(BOOL finished) {
  if (GSScreenDimmed) UIScreen.mainScreen.brightness = 0.0f;
 }];
}

void GSTriggerDimScreenForTest(void) {
 if (!NSThread.isMainThread) {
  dispatch_sync(dispatch_get_main_queue(), ^{ GSTriggerDimScreenForTest(); });
  return;
 }
 UIWindow *targetWindow = nil;
 for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
  if (![scene isKindOfClass:UIWindowScene.class]) continue;
  for (UIWindow *w in ((UIWindowScene *)scene).windows) {
   if (w.isKeyWindow) { targetWindow = w; break; }
  }
  if (targetWindow) break;
 }
 if (!targetWindow) targetWindow = UIApplication.sharedApplication.windows.firstObject;
 if (!targetWindow) return;

 if (!GSDimOverlayView) {
  GSDimOverlayView = [[GSDimOverlayViewClass alloc] initWithFrame:targetWindow.bounds];
  GSDimOverlayView.backgroundColor = UIColor.blackColor;
  GSDimOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
 }
 GSDimOverlayView.frame = targetWindow.bounds;
 if (GSDimOverlayView.superview != targetWindow) [targetWindow addSubview:GSDimOverlayView];
 [targetWindow bringSubviewToFront:GSDimOverlayView];

 if (GSOriginalBrightness < 0.0f) {
  GSOriginalBrightness = UIScreen.mainScreen.brightness;
 }
 GSScreenDimmed = YES;
 GSDimOverlayView.hidden = NO;
 GSDimOverlayView.alpha = 1.0f;
 UIScreen.mainScreen.brightness = 0.0f;
}

void GSRecordTouchForTest(void) {
 GSBackupLifecycleDidReceiveTouch();
}

static void GSResetIdleDimTimer(void) {
 NSCAssert(NSThread.isMainThread, @"Timer reset must run on main");
 [GSIdleDimTimer invalidate];
 GSIdleDimTimer = nil;

 BOOL active = GSSampleHostActive();
 BOOL foreground = GSUploadHostForeground();
 BOOL queueActive = GSUploadQueueActive();
 BOOL batchActive = [GSBatchImportSnapshot()[@"active"] boolValue];
 BOOL shouldKeepAwake = active && foreground && (queueActive || batchActive);

 if (shouldKeepAwake && GSBackupDimmingEnabled() && !GSScreenDimmed) {
  GSIdleDimTimer = [NSTimer scheduledTimerWithTimeInterval:GSDimInactivityInterval
                                                   repeats:NO
                                                     block:^(NSTimer *timer) {
   GSDimScreen();
  }];
 }
}

static void GSBackupLifecycleDidReceiveTouch(void) {
 if (!NSThread.isMainThread) {
  dispatch_async(dispatch_get_main_queue(), ^{
   GSBackupLifecycleDidReceiveTouch();
  });
  return;
 }
 if (GSScreenDimmed) {
  GSWakeScreen(YES);
  GSResetIdleDimTimer();
 } else {
  GSResetIdleDimTimer();
 }
}

static void (*GSOriginalSendEvent)(UIApplication *, SEL, UIEvent *);
static void GSSendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
 if (event.type == UIEventTypeTouches) {
  GSBackupLifecycleDidReceiveTouch();
 }
 if (GSOriginalSendEvent) GSOriginalSendEvent(self, _cmd, event);
}

static void GSInstallTouchMonitoring(void) {
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  Method sendEvent = class_getInstanceMethod(UIApplication.class, @selector(sendEvent:));
  if (sendEvent) {
   GSOriginalSendEvent = (void *)method_setImplementation(sendEvent, (IMP)GSSendEvent);
  }
 });
}

static void GSUpdateIdleTimer(void){
 NSCAssert(NSThread.isMainThread,@"Idle timer must run on main");
 BOOL foreground=GSUploadHostForeground();
 BOOL queueActive=GSUploadQueueActive();
 BOOL batchActive=[GSBatchImportSnapshot()[@"active"]boolValue];
 BOOL shouldKeepAwake=foreground&&(queueActive||batchActive);
 if(shouldKeepAwake){
  if(!UIApplication.sharedApplication.idleTimerDisabled){
   UIApplication.sharedApplication.idleTimerDisabled=YES;
  }
  GSGunshotAcquiredIdleTimer=YES;
  if (!GSScreenDimmed && !GSIdleDimTimer && GSSampleHostActive()) {
   GSResetIdleDimTimer();
  }
 }else{
  if(GSGunshotAcquiredIdleTimer){
   UIApplication.sharedApplication.idleTimerDisabled=NO;
   GSGunshotAcquiredIdleTimer=NO;
  }
  GSWakeScreen(NO);
 }
}

static void GSSampleHost(void){
 BOOL foreground=UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
  if(scene.activationState==UISceneActivationStateForegroundActive||scene.activationState==UISceneActivationStateForegroundInactive){foreground=YES;break;}
 GSSetUploadHostForeground(foreground);
 if (!GSSampleHostActive()) {
  GSWakeScreen(NO);
 }
 GSUpdateIdleTimer();
}

void GSStartBackupIntegration(void){
 if(!GSIsGooglePhotos())return;
 static dispatch_once_t once;dispatch_once(&once,^{
  GSInstallNativeRouting();GSInstallPhotosIntegration();
  GSInstallTouchMonitoring();
  for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationDidEnterBackgroundNotification,UIApplicationWillEnterForegroundNotification,UIApplicationWillResignActiveNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidEnterBackgroundNotification,UISceneWillEnterForegroundNotification])
   [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
    if([name isEqual:UIApplicationWillResignActiveNotification]||[name isEqual:UISceneWillDeactivateNotification]||[name isEqual:UIApplicationDidEnterBackgroundNotification]||[name isEqual:UISceneDidEnterBackgroundNotification]){
     GSWakeScreen(NO);
     [GSIdleDimTimer invalidate];
     GSIdleDimTimer=nil;
    }
    GSSampleHost();
   }];
  [NSNotificationCenter.defaultCenter addObserverForName:GSUploadMonitorStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSUpdateIdleTimer();}];
  GSSampleHost();
 });
}
