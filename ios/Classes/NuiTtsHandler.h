#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

@protocol NeoNuiTtsDelegate;

@interface NuiTtsHandler : NSObject <NeoNuiTtsDelegate>

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink;
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;

@property (nonatomic, copy) FlutterEventSink eventSink;

@end
