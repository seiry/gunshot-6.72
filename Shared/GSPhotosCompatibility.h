#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>

// Version metadata is informational. Each feature selects its own compatible ABI.
static inline BOOL GSPhotosHostSupported(void) {
 return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"];
}
static inline BOOL GSPhotosHostAudited(void) {
 id version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
 return GSPhotosHostSupported()&&([version isEqual:@"6.72.0"]||[version isEqual:@"6.72"]||[version isEqual:@"7.20.2"]||[version isEqual:@"7.92.0"]);
}
static inline BOOL GSPhotosHasMethod(Class cls,NSString *name,const char *abi) {
 Method method=class_getInstanceMethod(cls,NSSelectorFromString(name));
 return method&&!strcmp(method_getTypeEncoding(method),abi);
}
typedef NS_ENUM(NSUInteger, GSPhotosCompletionAPI) {
 GSPhotosCompletionUnavailable=0, GSPhotosCompletionObject, GSPhotosCompletionCode
};
static inline GSPhotosCompletionAPI GSPhotosCompletionForClass(Class cls) {
 if(GSPhotosHasMethod(cls,@"didCompleteWithSuccess:resultantMediaItem:error:","v36@0:8B16@20@28"))return GSPhotosCompletionObject;
 if(GSPhotosHasMethod(cls,@"didCompleteWithSuccess:resultantMediaItem:errorCode:","v36@0:8B16@20q28"))return GSPhotosCompletionCode;
 return GSPhotosCompletionUnavailable;
}
static inline NSString *GSPhotosAssetCompletion(Class cls) {
 switch(GSPhotosCompletionForClass(cls)){
 case GSPhotosCompletionObject:return @"didCompleteWithSuccess:resultantMediaItem:error:";
 case GSPhotosCompletionCode:return @"didCompleteWithSuccess:resultantMediaItem:errorCode:";
 default:return nil;
 }
}
static inline const char *GSPhotosAssetCompletionABI(Class cls) {
 return GSPhotosCompletionForClass(cls)==GSPhotosCompletionCode?"v36@0:8B16@20q28":"v36@0:8B16@20@28";
}
