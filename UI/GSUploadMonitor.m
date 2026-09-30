#import "GSUploadMonitor.h"
#import "GSNativeAccount.h"
#import "GSPhotosIntegration.h"
#import "../Shared/IPCProtocol.h"
NSString *const GSUploadMonitorStateDidChangeNotification=@"GSUploadMonitorStateDidChangeNotification";

// The host observes the same durable queue through either IPC or the embedded
// adapter. No panel, native backup request or active routing toggle is required.
static NSObject *GSLock;
static NSMutableDictionary *GSState;
static dispatch_queue_t GSQueue;
static BOOL GSForeground, GSInFlight;
static NSUInteger GSEpoch;
static NSString *GSLastIdentifier;
static NSNumber *GSLastRevision;

static void GSInitialize(void){
 static dispatch_once_t once;dispatch_once(&once,^{
  GSLock=[NSObject new];GSState=[@{@"started":@NO,@"foreground":@NO,@"polling":@NO,@"reachable":@NO,@"syncSignals":@0}mutableCopy];
  GSQueue=dispatch_queue_create("dev.tqmane.gunshot.upload-monitor",DISPATCH_QUEUE_SERIAL);
 });
}
static void GSRecord(NSDictionary *values){@synchronized(GSLock){[GSState addEntriesFromDictionary:values];}}
NSDictionary *GSUploadMonitorSnapshot(void){GSInitialize();@synchronized(GSLock){return [GSState copy];}}
BOOL GSUploadHostForeground(void){return [GSUploadMonitorSnapshot()[@"foreground"]boolValue];}
BOOL GSUploadQueueActive(void){
 NSDictionary *summary=GSUploadMonitorSnapshot()[@"uploadSummary"];
 if(![summary isKindOfClass:NSDictionary.class])return NO;
 NSDictionary *conditions=summary[@"conditions"];
 if([conditions isKindOfClass:NSDictionary.class]&&![conditions[@"online"]boolValue])return NO;
 NSDictionary *profiles=summary[@"profiles"];
 if([profiles isKindOfClass:NSDictionary.class]){
  for(id key in profiles){
   NSDictionary *mode=profiles[key];
   if(![mode isKindOfClass:NSDictionary.class])continue;
   NSDictionary *states=mode[@"states"];
   if(![states isKindOfClass:NSDictionary.class])continue;
   for(NSString *state in @[@"preparing",@"uploading",@"committing"]){
    NSNumber *count=states[state];
    if([count isKindOfClass:NSNumber.class]&&count.unsignedIntegerValue>0)return YES;
   }
  }
 }
 return NO;
}

static void GSPoll(void){
 NSCAssert(NSThread.isMainThread,@"Upload lifecycle must run on main");
 if(!GSForeground||GSInFlight)return;
 NSString *identifier=[GSNativeAccountSummary()[@"identifier"]copy];
 if(!identifier.length){
  if(GSUploadMonitorSnapshot()[@"uploadSummary"]){
   @synchronized(GSLock){[GSState removeObjectForKey:@"uploadSummary"];}
   [NSNotificationCenter.defaultCenter postNotificationName:GSUploadMonitorStateDidChangeNotification object:nil];
  }
  return;
 }
 NSUInteger epoch=GSEpoch;GSInFlight=YES;GSRecord(@{@"polling":@YES});
 dispatch_async(GSQueue,^{@autoreleasepool{
  NSDictionary *summary=GSRequest(@{@"op":@"upload_summary"},nil);
  dispatch_async(dispatch_get_main_queue(),^{
   GSInFlight=NO;GSRecord(@{@"polling":@NO,@"reachable":summary?@YES:@NO});
   // Do not acknowledge a response from an earlier foreground/account session.
   if(!GSForeground||epoch!=GSEpoch)return;
   BOOL identityMatched=GSNativeIdentityMatches(identifier);
   GSRecord(@{@"identityMatched":@(identityMatched)});
   if(!identityMatched||!summary){
    if(GSUploadMonitorSnapshot()[@"uploadSummary"]){
     @synchronized(GSLock){[GSState removeObjectForKey:@"uploadSummary"];}
     [NSNotificationCenter.defaultCenter postNotificationName:GSUploadMonitorStateDidChangeNotification object:nil];
    }
    return;
   }
   GSRecord(@{@"uploadSummary":summary});
   [NSNotificationCenter.defaultCenter postNotificationName:GSUploadMonitorStateDidChangeNotification object:nil];
   if(![summary[@"conditions"][@"online"]boolValue])return;
   NSNumber *revision=summary[@"completionRevision"];
   if(![revision isKindOfClass:NSNumber.class]||revision.unsignedLongLongValue==0)return;
   if([GSLastIdentifier isEqual:identifier]&&[GSLastRevision isEqual:revision])return;
   GSLastIdentifier=identifier;GSLastRevision=revision;
   GSRecord(@{@"syncSignals":@([GSUploadMonitorSnapshot()[@"syncSignals"]unsignedIntegerValue]+1)});
   // fetchData reads real server state; it never fabricates backup completion.
   GSRefreshNativeLibrary();
  });
 }});
}
void GSSetUploadHostForeground(BOOL foreground){
 NSCAssert(NSThread.isMainThread,@"Upload lifecycle must run on main");
 GSInitialize();
 static dispatch_once_t once;dispatch_once(&once,^{
  GSRecord(@{@"started":@YES});
  [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){GSPoll();}];
 });
 if(GSForeground!=foreground){
  GSEpoch++;GSLastIdentifier=nil;GSLastRevision=nil;
  if(!foreground)@synchronized(GSLock){[GSState removeObjectForKey:@"uploadSummary"];}
 }
 GSForeground=foreground;GSRecord(@{@"foreground":@(foreground)});
 [NSNotificationCenter.defaultCenter postNotificationName:GSUploadMonitorStateDidChangeNotification object:nil];
 GSPoll();
}
