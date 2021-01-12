//
//  AppDelegate.m
//  NativeDisplayBrightness
//
//  Created by Benno Krauss on 19.10.16.
//  Copyright © 2016 Benno Krauss. All rights reserved.
//

#import "AppDelegate.h"
#import "DDC.h"
#import "BezelServices.h"
#import "OSD.h"
#import "DDHotKeyCenter.h"

#include <dlfcn.h>

@import Carbon;

void *(*_BSDoGraphicWithMeterAndTimeout)(CGDirectDisplayID arg0, BSGraphic arg1, int arg2, float v, int timeout) = NULL;

#pragma mark - DDC

void set_control(CGDirectDisplayID cdisplay, uint control_id, uint new_value)
{
    struct DDCWriteCommand command;
    command.control_id = control_id;
    command.new_value = new_value;
    
    if (!DDCWrite(cdisplay, &command)){
        NSLog(@"E: Failed to send DDC command!");
    }
}

uint get_control(CGDirectDisplayID cdisplay, uint control_id, uint max_value)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = max_value;
    command.current_value = 0;
    
    if (!DDCRead(cdisplay, &command)){
        NSLog(@"E: Failed to send DDC command!");
    }
    return command.current_value;
}

#pragma mark - AppDelegate

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic) float brightness;
@property (strong, nonatomic) dispatch_source_t signalHandlerSource;
@end

@implementation AppDelegate
@synthesize brightness=_brightness;

static const float brightnessStep = 100/16.f;

- (BOOL)_loadBezelServices
{
    // Load BezelServices framework
    void *handle = dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/Versions/A/BezelServices", RTLD_GLOBAL);
    if (!handle) {
        NSLog(@"Error opening framework");
        return NO;
    }
    else {
        _BSDoGraphicWithMeterAndTimeout = dlsym(handle, "BSDoGraphicWithMeterAndTimeout");
        return _BSDoGraphicWithMeterAndTimeout != NULL;
    }
}

- (BOOL)_loadOSDFramework
{
    return [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"] load];
}

- (void)_registerHotKeys
{
    DDHotKeyCenter *hotKeyCenter = [DDHotKeyCenter sharedHotKeyCenter];
    [hotKeyCenter registerHotKeyWithKeyCode:144 modifierFlags:0 target:self action:@selector(increaseBrightness) object:nil];
    [hotKeyCenter registerHotKeyWithKeyCode:145 modifierFlags:0 target:self action:@selector(decreaseBrightness) object:nil];
}

- (void)_readBrightness
{
    CGDirectDisplayID display = CGSMainDisplayID();
    _brightness = get_control(display, BRIGHTNESS, 100);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (![self _loadBezelServices])
    {
        [self _loadOSDFramework];
    }

    [self _readBrightness];
    [self _registerHotKeys];
    [self _registerSignalHandling];
}

void shutdownSignalHandler(int signal)
{
}

- (void)_registerSignalHandling
{
    //Register signal callback that will gracefully shut the application down
    self.signalHandlerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(self.signalHandlerSource, ^{
        NSLog(@"Caught SIGTERM");
        [[NSApplication sharedApplication] terminate:self];
    });
    dispatch_resume(self.signalHandlerSource);
    
    //Register signal handler that will prevent the app from being killed
    signal(SIGTERM, shutdownSignalHandler);
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [self _willTerminate];
}

- (void)_willTerminate
{
    NSLog(@"willTerminate");
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication*) sender
{
    return NO;
}

- (void)setBrightness:(float)value
{
    _brightness = value;
    
    CGDirectDisplayID display = CGSMainDisplayID();
    
    if (_BSDoGraphicWithMeterAndTimeout != NULL)
    {
        // El Capitan and probably older systems
        _BSDoGraphicWithMeterAndTimeout(display, BSGraphicBacklightMeter, 0x0, value/100.f, 1);
    }
    else {
        // Sierra+
        [[NSClassFromString(@"OSDManager") sharedManager] showImage:OSDGraphicBacklight onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:value/brightnessStep totalChiclets:100.f/brightnessStep locked:NO];
    }
    
    for (NSScreen *screen in NSScreen.screens) {
        NSDictionary *description = [screen deviceDescription];
        if ([description objectForKey:@"NSDeviceIsScreen"]) {
            CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
            
            set_control(screenNumber, BRIGHTNESS, value);
        }
    }
}

- (float)brightness
{
    return _brightness;
}

- (void)increaseBrightness
{
    self.brightness = MIN(self.brightness+brightnessStep,100);
}

- (void)decreaseBrightness
{
    self.brightness = MAX(self.brightness-brightnessStep,0);
}

@end
