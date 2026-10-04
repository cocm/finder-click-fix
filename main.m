#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

@class AppDelegate;

typedef struct {
    AXUIElementRef system;
    CFMachPortRef tap;
    // The delegate owns this context and outlives its event tap.
    __unsafe_unretained AppDelegate *delegate;
    bool verbose;
} Context;

static double monotonic_seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

static bool prepare_ax_call(AXUIElementRef element, double deadline) {
    double remaining = deadline - monotonic_seconds();
    return remaining > 0 &&
        AXUIElementSetMessagingTimeout(element, (float)remaining) == kAXErrorSuccess;
}

static CFTypeRef copy_attribute(AXUIElementRef element, CFStringRef attribute,
                                double deadline) {
    CFTypeRef value = NULL;
    if (!prepare_ax_call(element, deadline) ||
        AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess)
        return NULL;
    return value;
}

static AXUIElementRef copy_element(AXUIElementRef element, CFStringRef attribute,
                                   double deadline) {
    CFTypeRef value = copy_attribute(element, attribute, deadline);
    if (!value) return NULL;
    if (CFGetTypeID(value) == AXUIElementGetTypeID())
        return (AXUIElementRef)value;
    CFRelease(value);
    return NULL;
}

static bool attribute_equals(AXUIElementRef element, CFStringRef attribute,
                             CFTypeRef expected, double deadline) {
    CFTypeRef value = copy_attribute(element, attribute, deadline);
    if (!value) return false;
    bool equal = CFEqual(value, expected);
    CFRelease(value);
    return equal;
}

static void focus_finder(Context *context, CGPoint point) {
    double started = monotonic_seconds();
    double deadline = started + 0.025;
    AXUIElementRef hit = NULL, window = NULL, app = NULL, focused = NULL;
    CFTypeRef value = NULL;
    pid_t pid = 0;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    int main_error = -1, front_error = -1, raise_error = -1;

    if (!prepare_ax_call(context->system, deadline) ||
        AXUIElementCopyElementAtPosition(context->system, (float)point.x,
                                         (float)point.y, &hit) != kAXErrorSuccess)
        goto done;
    if (AXUIElementGetPid(hit, &pid) != kAXErrorSuccess ||
        proc_pidpath(pid, path, sizeof(path)) <= 0 ||
        strcmp(path, "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        goto done;

    value = copy_attribute(hit, kAXRoleAttribute, deadline);
    if (!value) goto done;
    if (CFEqual(value, kAXSheetRole) || CFEqual(value, kAXDrawerRole)) goto done;
    if (CFEqual(value, kAXWindowRole))
        window = (AXUIElementRef)CFRetain(hit);
    CFRelease(value);
    value = NULL;
    if (!window) {
        window = copy_element(hit, kAXTopLevelUIElementAttribute, deadline);
        if (!window || !attribute_equals(window, kAXRoleAttribute, kAXWindowRole, deadline))
            goto done;
    }
    // Finder's desktop, menus and dialogs are outside this app's scope.
    if (!attribute_equals(window, kAXSubroleAttribute, kAXStandardWindowSubrole, deadline))
        goto done;

    app = AXUIElementCreateApplication(pid);
    value = copy_attribute(app, kAXFrontmostAttribute, deadline);
    if (!value) goto done;
    bool frontmost = CFEqual(value, kCFBooleanTrue);
    CFRelease(value);
    value = NULL;
    if (frontmost) {
        focused = copy_element(app, kAXFocusedWindowAttribute, deadline);
        if (!focused || CFEqual(focused, window)) goto done;
    }

    if (!prepare_ax_call(window, deadline)) goto done;
    main_error = AXUIElementSetAttributeValue(window, kAXMainAttribute, kCFBooleanTrue);
    if (main_error != kAXErrorSuccess) goto done;
    if (!prepare_ax_call(app, deadline)) goto done;
    front_error = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute, kCFBooleanTrue);
    if (front_error != kAXErrorSuccess) goto done;
    if (!prepare_ax_call(window, deadline)) goto done;
    raise_error = AXUIElementPerformAction(window, kAXRaiseAction);

done:
    if (context->verbose)
        fprintf(stderr, "Finder focus: elapsed=%.3f ms main=%d frontmost=%d raise=%d (-1=skipped)\n",
                (monotonic_seconds() - started) * 1000, main_error, front_error, raise_error);
    if (value) CFRelease(value);
    if (focused) CFRelease(focused);
    if (app) CFRelease(app);
    if (window) CFRelease(window);
    if (hit) CFRelease(hit);
}

static bool tap_is_running(Context *context) {
    return context->tap && CFMachPortIsValid(context->tap) && CGEventTapIsEnabled(context->tap);
}

static bool enable_tap(Context *context) {
    if (!context->tap || !CFMachPortIsValid(context->tap)) return false;
    if (!CGEventTapIsEnabled(context->tap)) CGEventTapEnable(context->tap, true);
    return tap_is_running(context);
}

static NSImage *inactive_icon(NSImage *base) {
    NSImage *badge = [NSImage imageWithSystemSymbolName:@"info.circle.fill" accessibilityDescription:nil];
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [base drawInRect:rect];
        CGContextRef graphics = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(graphics);
        CGContextSetBlendMode(graphics, kCGBlendModeClear);
        CGContextFillEllipseInRect(graphics, CGRectMake(8.5, 8.5, 10, 10));
        CGContextRestoreGState(graphics);
        [badge drawInRect:NSMakeRect(9.5, 9.5, 8.5, 8.5)];
        return YES;
    }];
    image.template = YES;
    return image;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    Context _context;
    CFRunLoopSourceRef _source;
    NSStatusItem *_statusItem;
    NSMenuItem *_stateItem;
    NSMenuItem *_permissionItem;
    NSTextField *_stateLabel;
    NSImageView *_stateSymbol;
    NSImage *_normalImage;
    NSImage *_inactiveImage;
    id _activationObserver;
}
- (instancetype)initWithVerbose:(bool)verbose;
- (NSMenu *)makeMenu;
- (void)updateStatus;
- (void)stopFix;
@end

static CGEventRef handle_event(CGEventTapProxy proxy, CGEventType type,
                              CGEventRef event, void *user_info) {
    (void)proxy;
    Context *context = user_info;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        bool running = enable_tap(context);
        [context->delegate updateStatus];
        if (!running && context->verbose)
            fprintf(stderr, "Finder Click Fix: event tap could not be re-enabled.\n");
    } else if (type == kCGEventLeftMouseDown) {
        focus_finder(context, CGEventGetLocation(event));
    }
    // Keep the actual button-down, including modifiers and double-click state.
    // Drag and button-up events never pass through this callback.
    return event;
}

@implementation AppDelegate
- (instancetype)initWithVerbose:(bool)verbose {
    self = [super init];
    if (self) {
        _context.verbose = verbose;
        _context.delegate = self;
    }
    return self;
}

- (void)updateStatus {
    bool trusted = AXIsProcessTrusted();
    bool running = trusted && tap_is_running(&_context);
    NSString *state = running ? @"Active" : trusted
        ? @"Inactive: Mouse input unavailable" : @"Inactive: Permission required";
    _stateItem.title = state;
    _stateLabel.stringValue = state;
    _stateSymbol.image = [NSImage imageWithSystemSymbolName:running ? @"checkmark.circle.fill" : @"info.circle.fill"
        accessibilityDescription:nil];
    _stateSymbol.contentTintColor = running ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    _statusItem.button.image = running ? _normalImage : _inactiveImage;
    _statusItem.button.toolTip = [@"Finder Click Fix — " stringByAppendingString:state];
    _statusItem.button.accessibilityValue = state;
    _permissionItem.hidden = running;
    if (_context.verbose) fprintf(stderr, "Finder Click Fix status: %s\n", state.UTF8String);
}

- (void)stopFix {
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_context.tap) {
        CFMachPortInvalidate(_context.tap);
        CFRelease(_context.tap);
        _context.tap = NULL;
    }
    if (_context.system) {
        CFRelease(_context.system);
        _context.system = NULL;
    }
}

- (void)startFix {
    if (!AXIsProcessTrusted()) {
        [self stopFix];
        [self updateStatus];
        return;
    }
    if (_context.tap) {
        if (CFMachPortIsValid(_context.tap)) {
            enable_tap(&_context);
            [self updateStatus];
            return;
        }
        [self stopFix];
    }
    _context.system = AXUIElementCreateSystemWide();
    _context.tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, CGEventMaskBit(kCGEventLeftMouseDown), handle_event, &_context);
    if (!_context.tap) {
        [self stopFix];
        [self updateStatus];
        return;
    }
    _source = CFMachPortCreateRunLoopSource(NULL, _context.tap, 0);
    if (!_source) {
        [self stopFix];
        [self updateStatus];
        return;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    if (!enable_tap(&_context)) {
        [self stopFix];
        [self updateStatus];
        return;
    }
    [self updateStatus];
    if (_context.verbose) fprintf(stderr, "Finder Click Fix is running.\n");
}

- (NSMenu *)makeMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Finder Click Fix"];
    menu.autoenablesItems = NO;
    menu.delegate = self;

    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 64)];
    NSTextField *name = [NSTextField labelWithString:@"Finder Click Fix"];
    name.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    name.frame = NSMakeRect(14, 38, 252, 18);
    [header addSubview:name];
    _stateSymbol = [[NSImageView alloc] initWithFrame:NSMakeRect(14, 14, 12, 12)];
    [header addSubview:_stateSymbol];
    _stateLabel = [NSTextField labelWithString:@""];
    _stateLabel.font = [NSFont systemFontOfSize:12];
    _stateLabel.frame = NSMakeRect(32, 11, 234, 18);
    [header addSubview:_stateLabel];
    _stateItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    _stateItem.enabled = NO;
    _stateItem.view = header;
    [menu addItem:_stateItem];
    [menu addItem:NSMenuItem.separatorItem];
    _permissionItem = [[NSMenuItem alloc] initWithTitle:@"Permission Settings…"
        action:@selector(openAccessibility:) keyEquivalent:@""];
    _permissionItem.target = self;
    [menu addItem:_permissionItem];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Finder Click Fix" action:@selector(terminate:) keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [menu addItem:quitItem];
    return menu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _normalImage = [NSBundle.mainBundle imageForResource:@"StatusIcon"];
    _normalImage.size = NSMakeSize(18, 18);
    _normalImage.template = YES;
    _inactiveImage = inactive_icon(_normalImage);
    _statusItem.button.accessibilityLabel = @"Finder Click Fix";
    _statusItem.menu = [self makeMenu];
    __weak AppDelegate *delegate = self;
    _activationObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [delegate startFix];
        }];
    [self startFix];
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    // Recheck on menu interaction and app activation, without a polling timer.
    [self startFix];
}

- (void)openAccessibility:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (_activationObserver) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_activationObserver];
        _activationObserver = nil;
    }
    [self stopFix];
}
@end

int main(int argc, char **argv) {
    bool check = false;
    bool verbose = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--check")) check = true;
        else if (!strcmp(argv[i], "--verbose")) verbose = true;
        else {
            fprintf(stderr, "Usage: FinderClickFix [--check] [--verbose]\n");
            return 2;
        }
    }
    if (check) {
        printf("Accessibility: %s\n", AXIsProcessTrusted() ? "allowed" : "not allowed");
        return AXIsProcessTrusted() ? 0 : 1;
    }
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) AppDelegate *delegate = [[AppDelegate alloc] initWithVerbose:verbose];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
