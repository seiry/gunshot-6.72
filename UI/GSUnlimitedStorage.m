#import "../Shared/GSPhotosCompatibility.h"
#import "GSUnlimitedStorage.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <stdatomic.h>

static NSString *const GSStoragePreference=@"GSShowUnlimitedStorage";
static const NSInteger GSNativeUnlimitedState=2;
static BOOL GSStorageInstalled, GSLegacyInstalled, GSBentoObserved;
static NSString *GSStorageStatus=@"not-installed";
static NSInteger (*GSOriginalModelState)(id,SEL);
static id (*GSOriginalModelTitle)(id,SEL), (*GSOriginalStorageTitle)(id,SEL,id), (*GSOriginalBentoController)(id,SEL);
static void (*GSOriginalModelEncode)(id,SEL,id), (*GSOriginalCellUpdate)(id,SEL,id);
static atomic_ulong GSModelStateReads, GSModelTitleReads, GSDisplayOverrides, GSArchiveCalls, GSBentoControllers, GSCellUpdates, GSTitleCalls;
static atomic_long GSNativeState=-1, GSDisplayState=-1, GSRenderedState=-1;
static atomic_bool GSStringsReady;
// Nested NSCoder calls must read native values; restored in @finally.
static _Thread_local NSUInteger GSStorageOriginalReads;
static NSObject *GSStorageLock;
static NSMutableOrderedSet *GSObservedCardClasses, *GSObservedControllerClasses;

BOOL GSUnlimitedStorageEnabled(void){
 id value=[NSUserDefaults.standardUserDefaults objectForKey:GSStoragePreference];
 return value==nil?YES:[value boolValue];
}
void GSSetUnlimitedStorage(BOOL enabled){[NSUserDefaults.standardUserDefaults setBool:enabled forKey:GSStoragePreference];}
BOOL GSUnlimitedStorageAvailable(void){return GSStorageInstalled;}
NSDictionary *GSUnlimitedStorageSnapshot(void){
 @synchronized(GSStorageLock){return @{@"implementation":@"native-display-model-v4",
  @"available":@(GSStorageInstalled),@"enabled":@(GSUnlimitedStorageEnabled()),@"status":GSStorageStatus,
  @"legacyObserver":@(GSLegacyInstalled),@"bentoObserver":@(GSBentoObserved),
  @"stringsReady":@(atomic_load(&GSStringsReady)),@"modelStateReads":@(atomic_load(&GSModelStateReads)),
  @"modelTitleReads":@(atomic_load(&GSModelTitleReads)),@"displayOverrides":@(atomic_load(&GSDisplayOverrides)),
  @"archiveCalls":@(atomic_load(&GSArchiveCalls)),@"bentoControllers":@(atomic_load(&GSBentoControllers)),
  @"cellUpdates":@(atomic_load(&GSCellUpdates)),@"titleCalls":@(atomic_load(&GSTitleCalls)),
  @"nativeStorageState":@(atomic_load(&GSNativeState)),@"displayStorageState":@(atomic_load(&GSDisplayState)),
  @"renderedStorageState":@(atomic_load(&GSRenderedState)),
  @"cardClasses":GSObservedCardClasses.array?:@[],@"controllerClasses":GSObservedControllerClasses.array?:@[]};}
}
static void GSStorageObserve(id object,NSMutableOrderedSet *classes){
 if(!object)return;NSString *name=NSStringFromClass(object_getClass(object));
 @synchronized(GSStorageLock){if(classes.count<16)[classes addObject:name];}
}
static BOOL GSStorageMethod(Class cls,NSString *name,const char *encoding){
 Method method=class_getInstanceMethod(cls,NSSelectorFromString(name));
 return method&&!strcmp(method_getTypeEncoding(method),encoding);
}
static BOOL GSStorageItem(id item){
 return [item isKindOfClass:NSClassFromString(@"OGLAccountSelectorStorageCardItem")]&&
  GSStorageMethod(object_getClass(item),@"storageState","q16@0:8");
}
static NSString *GSUnlimitedTitle(void){
 // Use stable native keys, not a numeric table index that can move in
 // later releases. OGLBundle is Google's own resolver in audited IPAs.
 id bundle=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"OGLBundle"),NSSelectorFromString(@"oneGoogleResourceBundle"));
 if(![bundle isKindOfClass:NSBundle.class]){atomic_store(&GSStringsReady,NO);return nil;}
 for(NSString *key in @[@"OneGoogleStorageCardUnlimitedTitle",@"OneGoogleStorageCardUnlimitedSubtitle"]){
  id title=[bundle localizedStringForKey:key value:key table:@"OneGoogle"];
  if([title isKindOfClass:NSString.class]&&[title length]&&![title isEqual:key]){
   atomic_store(&GSStringsReady,YES);return title;
  }
 }
 atomic_store(&GSStringsReady,NO);return nil;
}
static NSInteger GSStorageModelState(id object,SEL selector){
 NSInteger original=GSOriginalModelState(object,selector);
 if(GSStorageOriginalReads)return original;
 atomic_fetch_add(&GSModelStateReads,1);GSStorageObserve(object,GSObservedCardClasses);
 atomic_store(&GSNativeState,original);
 NSInteger display=original;
 if(GSUnlimitedStorageEnabled()&&GSUnlimitedTitle()){display=GSNativeUnlimitedState;atomic_fetch_add(&GSDisplayOverrides,1);}
 atomic_store(&GSDisplayState,display);return display;
}
static id GSStorageModelTitle(id object,SEL selector){
 if(GSStorageOriginalReads)return GSOriginalModelTitle(object,selector);
 atomic_fetch_add(&GSModelTitleReads,1);GSStorageObserve(object,GSObservedCardClasses);
 if(GSUnlimitedStorageEnabled()){NSString *title=GSUnlimitedTitle();if(title)return title;}
 return GSOriginalModelTitle(object,selector);
}
static void GSStorageModelEncode(id object,SEL selector,id coder){
 atomic_fetch_add(&GSArchiveCalls,1);GSStorageOriginalReads++;
 @try{GSOriginalModelEncode(object,selector,coder);}@finally{GSStorageOriginalReads--;}
}
static id GSStorageBentoController(id object,SEL selector){
 id controller=GSOriginalBentoController(object,selector);
 atomic_fetch_add(&GSBentoControllers,1);GSStorageObserve(controller,GSObservedControllerClasses);return controller;
}
static void GSStorageCellUpdate(id object,SEL selector,id item){
 atomic_fetch_add(&GSCellUpdates,1);
 if(GSStorageItem(item))atomic_store(&GSRenderedState,((NSInteger(*)(id,SEL))objc_msgSend)(item,NSSelectorFromString(@"storageState")));
 GSOriginalCellUpdate(object,selector,item);
}
static id GSStorageTitle(id cls,SEL selector,id item){
 atomic_fetch_add(&GSTitleCalls,1);
 if(GSUnlimitedStorageEnabled()&&GSStorageItem(item)&&
    ((NSInteger(*)(id,SEL))objc_msgSend)(item,NSSelectorFromString(@"storageState"))==GSNativeUnlimitedState){
  NSString *title=GSUnlimitedTitle();if(title)return title;
 }
 return GSOriginalStorageTitle(cls,selector,item);
}
static IMP GSStorageReplace(Class cls,SEL selector,IMP replacement){
 Method method=class_getInstanceMethod(cls,selector);IMP original=method_getImplementation(method);
 if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))method_setImplementation(method,replacement);
 return original;
}
void GSInstallUnlimitedStorage(void){
 if(GSStorageInstalled)return;
 if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"]||
    !GSPhotosHostSupported()){GSStorageStatus=@"unsupported-host";return;}
 Class data=NSClassFromString(@"OGLAccountMenuStorageCardData"),bundle=NSClassFromString(@"OGLBundle");
 BOOL modelTitle=GSStorageMethod(data,@"title","@16@0:8");
 GSStorageStatus=@"incompatible-model-abi";
 if(!GSStorageMethod(data,@"storageState","q16@0:8")||(class_getInstanceMethod(data,NSSelectorFromString(@"title"))&&!modelTitle)||!GSStorageMethod(data,@"encodeWithCoder:","v24@0:8@16"))return;
 GSStorageStatus=@"incompatible-resources-abi";
 if(!GSStorageMethod(object_getClass(bundle),@"oneGoogleResourceBundle","@16@0:8"))return;
 // A model without a title getter requires the native UIKit title path.
 if(!modelTitle&&(!GSStorageMethod(NSClassFromString(@"OGLAccountSelectorStorageCardItem"),@"storageState","q16@0:8")||
  !GSStorageMethod(object_getClass(NSClassFromString(@"OGLAccountSelectorStorageCardCell")),@"titleTextWithStorageItem:","@24@0:8@16")||
  !GSStorageMethod(NSClassFromString(@"OGLAccountSelectorStorageCardCell"),@"updateWithItem:","v24@0:8@16"))){GSStorageStatus=@"incompatible-legacy-cell-abi";return;}
 GSStorageLock=[NSObject new];GSObservedCardClasses=[NSMutableOrderedSet orderedSet];GSObservedControllerClasses=[NSMutableOrderedSet orderedSet];
 // UIKit and Bento share these display getters. Preserve the stored model,
 // account quota and callback identities.
 GSOriginalModelState=(void *)GSStorageReplace(data,NSSelectorFromString(@"storageState"),(IMP)GSStorageModelState);
 if(modelTitle)GSOriginalModelTitle=(void *)GSStorageReplace(data,NSSelectorFromString(@"title"),(IMP)GSStorageModelTitle);
 GSOriginalModelEncode=(void *)GSStorageReplace(data,NSSelectorFromString(@"encodeWithCoder:"),(IMP)GSStorageModelEncode);
 // Optional: Bento does not use the legacy UIKit converter or cell.
 Class item=NSClassFromString(@"OGLAccountSelectorStorageCardItem"),cell=NSClassFromString(@"OGLAccountSelectorStorageCardCell");
 if(GSStorageMethod(item,@"storageState","q16@0:8")&&GSStorageMethod(object_getClass(cell),@"titleTextWithStorageItem:","@24@0:8@16")&&GSStorageMethod(cell,@"updateWithItem:","v24@0:8@16")){
  GSOriginalStorageTitle=(void *)GSStorageReplace(object_getClass(cell),NSSelectorFromString(@"titleTextWithStorageItem:"),(IMP)GSStorageTitle);
  GSOriginalCellUpdate=(void *)GSStorageReplace(cell,NSSelectorFromString(@"updateWithItem:"),(IMP)GSStorageCellUpdate);GSLegacyInstalled=YES;
 }
 Class bento=NSClassFromString(@"OGLBentoAccountMenuFactory");
 if(GSStorageMethod(bento,@"makeBentoAccountMenuViewController","@16@0:8")){
  GSOriginalBentoController=(void *)GSStorageReplace(bento,NSSelectorFromString(@"makeBentoAccountMenuViewController"),(IMP)GSStorageBentoController);GSBentoObserved=YES;
 }
 GSStorageInstalled=YES;GSStorageStatus=@"installed";
}
