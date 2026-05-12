#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import "nuisdk.framework/Headers/NeoNui.h"
#import "nuisdk.framework/Headers/NeoNuiCode.h"

@interface NuiAsrHandler : NSObject <NeoNuiSdkDelegate>

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink;
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;

@property (nonatomic, copy) FlutterEventSink eventSink;

@end
