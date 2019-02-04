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
#include <dlfcn.h>
// [tomun
#import "DDHotKeyCenter.h"
// ]tomun

@import Carbon;

#pragma mark - constants

static NSString *brightnessValuePreferenceKey = @"brightness";
static const float brightnessStep = 100/16.f;

// [tomun
static const UInt32 vkBrightnessUp = 144;
static const UInt32 vkBrightnessDown = 145;
// ]tomun

#pragma mark - variables

void *(*_BSDoGraphicWithMeterAndTimeout)(CGDirectDisplayID arg0, BSGraphic arg1, int arg2, float v, int timeout) = NULL;

#pragma mark - functions

void set_control(CGDirectDisplayID cdisplay, uint control_id, uint new_value)
{
    struct DDCWriteCommand command;
    command.control_id = control_id;
    command.new_value = new_value;
    
    if (!DDCWrite(cdisplay, &command)){
        NSLog(@"E: Failed to send DDC command!");
    }
}

// [tomun
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
// ]tomun

CGEventRef keyboardCGEventCallback(CGEventTapProxy proxy,
                             CGEventType type,
                             CGEventRef event,
                             void *refcon)
{
    //Surpress the F1/F2 key events to prevent other applications from catching it or playing beep sound
    if (type == NX_KEYDOWN || type == NX_KEYUP || type == NX_FLAGSCHANGED)
    {
        int64_t keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (keyCode == kVK_F2 || keyCode == kVK_F1)
        {
            return NULL;
        }
    }
    return event;
}

#pragma mark - AppDelegate

@interface AppDelegate ()
// [tomun
{
    NSStatusItem  *_statusItem;
    NSView        *_brightnessSliderContainer;
    NSSlider      *_brightnessSlider;
    NSView        *_contrastSliderContainer;
    NSSlider      *_contrastSlider;
}
// ]tomun
@property (weak) IBOutlet NSWindow *window;
@property (nonatomic) float brightness;
// [tomun
@property (nonatomic) float contrast;
// ]tomun
@property (strong, nonatomic) dispatch_source_t signalHandlerSource;
@end

@implementation AppDelegate
@synthesize brightness=_brightness;
// [tomun
@synthesize contrast=_contrast;
// ]tomun

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

- (void)_configureLoginItem
{
    NSURL *bundleURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    LSSharedFileListRef loginItemsListRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    NSDictionary *properties = @{@"com.apple.loginitem.HideOnLaunch": @YES};
    LSSharedFileListInsertItemURL(loginItemsListRef, kLSSharedFileListItemLast, NULL, NULL, (__bridge CFURLRef)bundleURL, (__bridge CFDictionaryRef)properties,NULL);
}

- (void)_checkTrusted
{
    BOOL isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @true});
    NSLog(@"istrusted: %i",isTrusted);
}

- (void)_registerGlobalKeyboardEvents
{
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^(NSEvent *_Nonnull event) {
        //NSLog(@"event!!");
        if (event.keyCode == kVK_F1)
        {
            if (event.type == NSEventTypeKeyDown)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self decreaseBrightness];
                });
            }
        }
        else if (event.keyCode == kVK_F2)
        {
            if (event.type == NSEventTypeKeyDown)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self increaseBrightness];
                });
            }
        }
    }];
    
    CFRunLoopRef runloop = (CFRunLoopRef)CFRunLoopGetCurrent();
    CGEventMask interestedEvents = NX_KEYDOWNMASK | NX_KEYUPMASK | NX_FLAGSCHANGEDMASK;
    CFMachPortRef eventTap = CGEventTapCreate(kCGAnnotatedSessionEventTap, kCGHeadInsertEventTap,
                                              kCGEventTapOptionDefault, interestedEvents, keyboardCGEventCallback, (__bridge void * _Nullable)(self));
    // by passing self as last argument, you can later send events to this class instance
    
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,
                                                              eventTap, 0);
    CFRunLoopAddSource((CFRunLoopRef)runloop, source, kCFRunLoopCommonModes);
    
    CGEventTapEnable(eventTap, true);
}

// [tomun
- (void)_registerHotKeys
{
    DDHotKeyCenter *hotKeyCenter = [DDHotKeyCenter sharedHotKeyCenter];
    [hotKeyCenter registerHotKeyWithKeyCode:vkBrightnessUp
                              modifierFlags:0
                                     target:self
                                     action:@selector(increaseBrightness)
                                     object:nil];
    [hotKeyCenter registerHotKeyWithKeyCode:vkBrightnessDown
                              modifierFlags:0
                                     target:self
                                     action:@selector(decreaseBrightness)
                                     object:nil];
    [hotKeyCenter registerHotKeyWithKeyCode:vkBrightnessUp
                              modifierFlags:NSShiftKeyMask
                                     target:self
                                     action:@selector(increaseContrast)
                                     object:nil];
    [hotKeyCenter registerHotKeyWithKeyCode:vkBrightnessDown
                              modifierFlags:NSShiftKeyMask
                                     target:self
                                     action:@selector(decreaseContrast)
                                     object:nil];
}

- (void)_readMonitorSettings
{
    CGDirectDisplayID display = CGSMainDisplayID();
    _brightness = get_control(display, BRIGHTNESS, 100);
    _contrast = get_control(display, CONTRAST, 100);
}

- (void)_createMenuBarIcon
{
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    _statusItem = [statusBar statusItemWithLength:NSSquareStatusItemLength];

    NSImage *icon = [NSImage imageNamed:@"touchBarBrightnessUp"];
    icon.size = NSMakeSize(18.0, 18.0);
    icon.template = YES;

    _statusItem.image = icon;
    _statusItem.highlightMode = YES;
    _statusItem.enabled = YES;

    _statusItem.menu = [self _createStatusBarMenu];
}

static const CGFloat SliderWidth = 160;
static const CGFloat SliderHeight = 22;
static const CGFloat MenuLeftPadding = 20;
static const CGFloat MenuRightPadding = 16;

- (NSMenu *)_createStatusBarMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    // Brightness
    NSMenuItem *sliderLabelItem =
    [[NSMenuItem alloc] initWithTitle:@"Brightness:"
                               action:nil
                        keyEquivalent:@""];
    [menu addItem:sliderLabelItem];

    _brightnessSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(MenuLeftPadding, 0, SliderWidth, SliderHeight)];
    [_brightnessSlider setMinValue:0];
    [_brightnessSlider setMaxValue:100];
    [_brightnessSlider setDoubleValue:_brightness];
    [_brightnessSlider setTarget:self];
    [_brightnessSlider setAction:@selector(_brightnessSliderChanged:)];
    _brightnessSliderContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MenuLeftPadding + SliderWidth + MenuRightPadding, SliderHeight)];
    [_brightnessSliderContainer addSubview:_brightnessSlider];
    NSMenuItem *sliderItem = [[NSMenuItem alloc] init];
    sliderItem.view = _brightnessSliderContainer;
    [menu addItem:sliderItem];

    // Contrast
    NSMenuItem *contrastSliderLabelItem =
    [[NSMenuItem alloc] initWithTitle:@"Contrast:"
                               action:nil
                        keyEquivalent:@""];
    [menu addItem:contrastSliderLabelItem];
    
    _contrastSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(MenuLeftPadding, 0, SliderWidth, SliderHeight)];
    [_contrastSlider setMinValue:0];
    [_contrastSlider setMaxValue:100];
    [_contrastSlider setDoubleValue:_contrast];
    [_contrastSlider setTarget:self];
    [_contrastSlider setAction:@selector(_brightnessSliderChanged:)];
    _contrastSliderContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MenuLeftPadding + SliderWidth + MenuRightPadding, SliderHeight)];
    [_contrastSliderContainer addSubview:_contrastSlider];
    NSMenuItem *contrastSliderItem = [[NSMenuItem alloc] init];
    contrastSliderItem.view = _contrastSliderContainer;
    [menu addItem:contrastSliderItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *reset =
    [[NSMenuItem alloc] initWithTitle:@"Reset"
                               action:@selector(_reset)
                        keyEquivalent:@""];
    [reset setTarget:self];
    [menu addItem:reset];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *about =
        [[NSMenuItem alloc] initWithTitle:@"About"
                                   action:@selector(_about)
                            keyEquivalent:@""];
    [about setTarget:self];
    [menu addItem:about];

    NSMenuItem *quit =
        [[NSMenuItem alloc] initWithTitle:@"Quit"
                                   action:@selector(_quit)
                            keyEquivalent:@""];
    [quit setTarget:self];
    [menu addItem:quit];

    return menu;
}

- (void)_reset
{
    [self setBrightness:75];
    [self setContrast:75];
}

- (void)_about
{
    [NSApp activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:self];
}

- (void)_quit
{
	[[NSApplication sharedApplication] terminate:self];
}

- (void)_brightnessSliderChanged:(id)sender
{
    if (sender == _brightnessSlider) {
        [self setBrightness:[_brightnessSlider floatValue]];
    } else if (sender == _contrastSlider) {
        [self setContrast:[_contrastSlider floatValue]];
    }
}
// ]tomun

- (void)_saveBrightness
{
    [[NSUserDefaults standardUserDefaults] setFloat:self.brightness forKey:brightnessValuePreferenceKey];
}

- (void)_loadBrightness
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        brightnessValuePreferenceKey: @(8*brightnessStep)
    }];
    
    _brightness = [[NSUserDefaults standardUserDefaults] floatForKey:brightnessValuePreferenceKey];
    NSLog(@"Loaded value: %f",_brightness);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (![self _loadBezelServices])
    {
        [self _loadOSDFramework];
    }
    [self _configureLoginItem];
    // [tomun
    // [self _checkTrusted];
    // [self _registerGlobalKeyboardEvents];
    // [self _loadBrightness];
    [self _readMonitorSettings];
    [self _registerHotKeys];
    [self _createMenuBarIcon];
    // ]tomun
    [self _registerSignalHandling];
}

void shutdownSignalHandler(int signal)
{
    //Don't do anything
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
    // [tomun
    //[self _saveBrightness];
    // ]tomun
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
    
    // [tomun
    [_brightnessSlider setDoubleValue:_brightness];
    // ]tomun
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

// [tomun
- (void)setContrast:(float)value
{
    _contrast = value;

    for (NSScreen *screen in NSScreen.screens) {
        NSDictionary *description = [screen deviceDescription];
        if ([description objectForKey:@"NSDeviceIsScreen"]) {
            CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
            
            set_control(screenNumber, CONTRAST, value);
        }
    }
    
    [_contrastSlider setDoubleValue:_contrast];
}

- (float)contrast
{
    return _contrast;
}

- (void)increaseContrast
{
    self.contrast = MIN(self.contrast+brightnessStep,100);
}

- (void)decreaseContrast
{
    self.contrast = MAX(self.contrast-brightnessStep,0);
}
// ]tomun
@end
