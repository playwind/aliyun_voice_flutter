#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import "nuisdk.framework/Headers/NeoNuiTts.h"
#import "nuisdk.framework/Headers/NeoNuiCode.h"

@interface NuiTtsHandler : NSObject <NeoNuiTtsDelegate>

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink;
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;

@property (nonatomic, copy) FlutterEventSink eventSink;

@end
