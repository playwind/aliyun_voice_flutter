#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface AliyunVoicePlugin : NSObject <FlutterPlugin, FlutterStreamHandler>

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar;

@end

NS_ASSUME_NONNULL_END
