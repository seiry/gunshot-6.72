#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "host_profile.h"
#import "native_account_fixture.h"
#import "../UI/GSUploadMonitor.h"
#import "../UI/GSPhotosIntegration.h"
#include <assert.h>
#include <stdatomic.h>

static atomic_bool online=YES,reachable=YES,holdReply=NO,waiting=NO;
static atomic_ulong revision,requests;
static dispatch_semaphore_t releaseReply;
static NSDictionary *customProfiles;
BOOL GSIsGooglePhotos(void){return YES;}
BOOL GSNativeRoutingEnabled(void){return NO;} // Standalone GoToHP uploads also sync.
@interface FixtureBundle : NSBundle @end
@implementation FixtureBundle
- (id)objectForInfoDictionaryKey:(NSString *)key{return [key isEqual:@"CFBundleExecutable"]?@"GooglePhotos":GSFixtureVersion;}
@end
static id Bundle(id object,SEL selector){return [FixtureBundle new];}
@interface PHSUserItemsSynchronizer : NSObject
@property(nonatomic,strong) id accountID;
@property(nonatomic) NSUInteger fetches;
- (void)fetchData;
@end
@implementation PHSUserItemsSynchronizer
- (void)fetchData{assert(NSThread.isMainThread);self.fetches++;}
@end
NSDictionary *GSRequest(NSDictionary *request,NSError **error){
 assert(!NSThread.isMainThread);assert([request[@"op"]isEqual:@"upload_summary"]);requests++;
 NSMutableDictionary *summary=[@{@"completionRevision":@(atomic_load(&revision)),@"conditions":@{@"online":@(atomic_load(&online))}} mutableCopy];
 if(customProfiles)summary[@"profiles"]=customProfiles;
 if(atomic_load(&holdReply)){waiting=YES;dispatch_semaphore_wait(releaseReply,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));waiting=NO;}
 return atomic_load(&reachable)?summary:nil;
}
static void Await(BOOL(^done)(void)){
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:6];
 while(!done()&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 assert(done());
}
static void Poll(void){
 unsigned long before=requests;GSSetUploadHostForeground(YES);
 Await(^BOOL{return requests>before&&![GSUploadMonitorSnapshot()[@"polling"]boolValue];});
}
int main(void){@autoreleasepool{
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)Bundle);
 GSFixtureSelectAccount(nil);
 PHSAccount *accountA=GSFixtureMakeAccount(@"fixture-user-A",@"a@example.com");
 PHSAccount *accountB=GSFixtureMakeAccount(@"fixture-user-B",@"b@example.com");
 GSInstallPhotosIntegration();assert([GSPhotosIntegrationSnapshot()[@"syncAvailable"]boolValue]);
 PHSUserItemsSynchronizer *a=[PHSUserItemsSynchronizer new];a.accountID=[[GIPGaiaAccountID alloc]initWithGaiaID:@"fixture-user-A"];[a fetchData];
 PHSUserItemsSynchronizer *b=[PHSUserItemsSynchronizer new];b.accountID=[[GIPGaiaAccountID alloc]initWithGaiaID:@"fixture-user-B"];[b fetchData];
 GSSetUploadHostForeground(YES);assert(requests==0); // Delayed native sign-in.
 GSFixtureSelectAccount(accountA);Poll();assert(a.fetches==1&&b.fetches==1); // Empty revision is not a completion.
 assert([GSNativeAccountSummary()[@"identifier"]isEqual:@"fixture-user-A"]);
 assert(GSNativeAccountMatches(a.accountID)&&!GSNativeAccountMatches(@"fixture-user-A"));
 revision=1;Poll();assert([GSUploadMonitorSnapshot()[@"uploadSummary"][@"completionRevision"]unsignedLongLongValue]==1);Await(^BOOL{return a.fetches==2;});assert(b.fetches==1);
 assert(!GSUploadQueueActive());
 customProfiles=@{@"original":@{@"states":@{@"pending":@5}}};Poll();assert(!GSUploadQueueActive()); // Pending/paused alone does not keep awake.
 customProfiles=@{@"original":@{@"states":@{@"uploading":@1}}};Poll();assert(GSUploadQueueActive());
 online=NO;Poll();assert(!GSUploadQueueActive()); // Offline releases keep-awake.
 online=YES;Poll();assert(GSUploadQueueActive());
 GSFixtureSelectAccount(nil);Poll();assert(!GSUploadQueueActive()); // Auth loss releases keep-awake.
 GSFixtureSelectAccount(accountA);
 customProfiles=@{@"original":@{@"states":@{@"completed":@1}}};Poll();assert(!GSUploadQueueActive());
 customProfiles=nil;
 Poll();assert(a.fetches==2&&[GSUploadMonitorSnapshot()[@"syncSignals"]integerValue]==1);
 online=NO;revision=2;Poll();assert([GSUploadMonitorSnapshot()[@"syncSignals"]integerValue]==1);
 online=YES;Poll();Await(^BOOL{return a.fetches==3;});
 reachable=NO;revision=3;Poll();assert(a.fetches==3&&![GSUploadMonitorSnapshot()[@"reachable"]boolValue]);
 reachable=YES;Poll();Await(^BOOL{return a.fetches==4;});

 // A late response after an account switch must not acknowledge the new
 // account's revision or request a sync on its behalf.
 releaseReply=dispatch_semaphore_create(0);holdReply=YES;revision=4;
 GSSetUploadHostForeground(YES);Await(^BOOL{return atomic_load(&waiting);});
 unsigned long before=requests;GSSetUploadHostForeground(YES);assert(requests==before); // Coalesced in flight.
 NSDictionary *snapshot=GSUploadMonitorSnapshot();assert([snapshot[@"polling"]boolValue]); // Nonblocking during RPC.
 GSFixtureSelectAccount(accountB);holdReply=NO;dispatch_semaphore_signal(releaseReply);
 Await(^BOOL{return ![GSUploadMonitorSnapshot()[@"polling"]boolValue];});assert(b.fetches==1);
 assert(![GSUploadMonitorSnapshot()[@"identityMatched"]boolValue]);
 Poll();Await(^BOOL{return b.fetches==2;});assert(a.fetches==4);
 GSFixtureSelectAccount(accountA);Poll();Await(^BOOL{return a.fetches==5;}); // Same revision, different current account.

 // Work completed while the host was stopped is observed on foreground entry.
 GSSetUploadHostForeground(NO);before=requests;revision=5;
 [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];assert(requests==before);
 Poll();Await(^BOOL{return a.fetches==6;});
 // Dropping into background while IPC waits cannot consume a completion.
 holdReply=YES;revision=6;GSSetUploadHostForeground(YES);Await(^BOOL{return atomic_load(&waiting);});
 GSSetUploadHostForeground(NO);holdReply=NO;dispatch_semaphore_signal(releaseReply);
 Await(^BOOL{return ![GSUploadMonitorSnapshot()[@"polling"]boolValue];});assert(a.fetches==6);
 Poll();Await(^BOOL{return a.fetches==7;});
 // An account object can remain available after its authorization expires.
 ((GSFixtureIdentity *)accountA->_ssoIdentity).hasValidAuth=NO;
 before=requests;revision=7;GSSetUploadHostForeground(YES);assert(requests==before);
 ((GSFixtureIdentity *)accountA->_ssoIdentity).hasValidAuth=YES;
 Poll();Await(^BOOL{return a.fetches==8;});
 GSFixtureSelectAccount(nil);before=requests;GSSetUploadHostForeground(YES);assert(requests==before);
 NSString *json=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:GSUploadMonitorSnapshot() options:0 error:nil] encoding:NSUTF8StringEncoding];
 assert(![json containsString:@"fixture-user-A"]&&![json containsString:@"fixture-user-B"]);
 GSSetUploadHostForeground(NO);
 NSLog(@"PASS completion monitoring without settings, delayed sign-in, offline/IPC recovery, account switch, late replies, background completion, coalescing and private diagnostics");
 return 0;
}}
