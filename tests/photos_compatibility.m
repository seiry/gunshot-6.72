#import "../Shared/GSPhotosCompatibility.h"
#include <assert.h>
static id version;
static NSString *executable=@"GooglePhotos";
@interface FixtureBundle : NSObject @end
@implementation FixtureBundle
- (id)objectForInfoDictionaryKey:(NSString *)key{return [key isEqual:@"CFBundleExecutable"]?executable:version;}
@end
static id Bundle(id object,SEL selector){return [FixtureBundle new];}
static void Done(id object,SEL selector,BOOL success,id result,id error){}
static Class Fixture(const char *name,const char *selector,const char *abi){
 Class cls=objc_allocateClassPair(NSObject.class,name,0);
 if(selector)class_addMethod(cls,sel_registerName(selector),(IMP)Done,abi);
 objc_registerClassPair(cls);return cls;
}
int main(void){@autoreleasepool{
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)Bundle);
 Class legacy=Fixture("LegacyCompletion","didCompleteWithSuccess:resultantMediaItem:errorCode:","v36@0:8B16@20q28");
 Class modern=Fixture("ModernCompletion","didCompleteWithSuccess:resultantMediaItem:error:","v36@0:8B16@20@28");
 Class wrong=Fixture("WrongCompletion","didCompleteWithSuccess:resultantMediaItem:error:","v36@0:8B16@20q28");
 Class absent=Fixture("MissingCompletion",NULL,NULL);
 for(id value in @[@123,NSNull.null,@"",@"6.72.0",@"6.72",@"7.20.1",@"7.20.2",@"7.50",@"7.92.0",@"8.0",@"unknown"]){
  version=value;assert(GSPhotosHostSupported());
  assert(GSPhotosCompletionForClass(legacy)==GSPhotosCompletionCode);
  assert(GSPhotosCompletionForClass(modern)==GSPhotosCompletionObject);
  assert(GSPhotosCompletionForClass(wrong)==GSPhotosCompletionUnavailable);
  assert(GSPhotosCompletionForClass(absent)==GSPhotosCompletionUnavailable);
  assert(GSPhotosHostAudited()==([value isEqual:@"6.72.0"]||[value isEqual:@"6.72"]||[value isEqual:@"7.20.2"]||[value isEqual:@"7.92.0"]));
 }
 // Mixed generations are selected per class; modern wins only with a valid ABI.
 class_addMethod(legacy,sel_registerName("didCompleteWithSuccess:resultantMediaItem:error:"),(IMP)Done,"v36@0:8B16@20@28");
 assert(GSPhotosCompletionForClass(legacy)==GSPhotosCompletionObject);
 class_addMethod(wrong,sel_registerName("didCompleteWithSuccess:resultantMediaItem:errorCode:"),(IMP)Done,"v36@0:8B16@20q28");
 assert(GSPhotosCompletionForClass(wrong)==GSPhotosCompletionCode);
 executable=@"OtherApp";assert(!GSPhotosHostSupported()&&!GSPhotosHostAudited());
 NSLog(@"PASS API-based completion selection, mixed generations, incompatible ABI and informational versions");
}}
