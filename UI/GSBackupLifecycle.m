#import <UIKit/UIKit.h>
#import "GSUploadMonitor.h"
#import "GSBatchImport.h"
#import "GSNativeRouting.h"
#import "GSPhotosIntegration.h"

static BOOL GSGunshotAcquiredIdleTimer;
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
 }else if(GSGunshotAcquiredIdleTimer){
  UIApplication.sharedApplication.idleTimerDisabled=NO;
  GSGunshotAcquiredIdleTimer=NO;
 }
}
static void GSSampleHost(void){
 BOOL foreground=UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
  if(scene.activationState==UISceneActivationStateForegroundActive||scene.activationState==UISceneActivationStateForegroundInactive){foreground=YES;break;}
 GSSetUploadHostForeground(foreground);
 GSUpdateIdleTimer();
}
void GSStartBackupIntegration(void){
 if(!GSIsGooglePhotos())return;
 static dispatch_once_t once;dispatch_once(&once,^{
  GSInstallNativeRouting();GSInstallPhotosIntegration();
  for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationDidEnterBackgroundNotification,UIApplicationWillEnterForegroundNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidEnterBackgroundNotification,UISceneWillEnterForegroundNotification])
   [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSSampleHost();}];
  [NSNotificationCenter.defaultCenter addObserverForName:GSUploadMonitorStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSUpdateIdleTimer();}];
  GSSampleHost();
 });
}
