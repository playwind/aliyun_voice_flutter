#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <nuisdk/NeoNui.h>
#import <nuisdk/NeoNuiCode.h>

@interface NuiAsrHandler : NSObject <NeoNuiSdkDelegate>

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink;
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;

@property (nonatomic, copy) FlutterEventSink eventSink;

@end
