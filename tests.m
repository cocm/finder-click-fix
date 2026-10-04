#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <libproc.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// Replace OS interactions only in this test translation unit. No events are posted.
static int fake_clock_gettime(clockid_t, struct timespec *);
static int fake_proc_pidpath(int, void *, uint32_t);
static Boolean fake_AXIsProcessTrusted(void);
static AXUIElementRef fake_AXUIElementCreateSystemWide(void);
static AXUIElementRef fake_AXUIElementCreateApplication(pid_t);
static AXError fake_AXUIElementSetMessagingTimeout(AXUIElementRef, float);
static AXError fake_AXUIElementCopyElementAtPosition(AXUIElementRef, float, float, AXUIElementRef *);
static AXError fake_AXUIElementGetPid(AXUIElementRef, pid_t *);
static AXError fake_AXUIElementCopyAttributeValue(AXUIElementRef, CFStringRef, CFTypeRef *);
static AXError fake_AXUIElementSetAttributeValue(AXUIElementRef, CFStringRef, CFTypeRef);
static AXError fake_AXUIElementPerformAction(AXUIElementRef, CFStringRef);
static CFMachPortRef fake_CGEventTapCreate(CGEventTapLocation, CGEventTapPlacement,
    CGEventTapOptions, CGEventMask, CGEventTapCallBack, void *);
static Boolean fake_CFMachPortIsValid(CFMachPortRef);
static void fake_CFMachPortInvalidate(CFMachPortRef);
static CFRunLoopSourceRef fake_CFMachPortCreateRunLoopSource(CFAllocatorRef, CFMachPortRef, CFIndex);
static bool fake_CGEventTapIsEnabled(CFMachPortRef);
static void fake_CGEventTapEnable(CFMachPortRef, bool);

#define clock_gettime fake_clock_gettime
#define proc_pidpath fake_proc_pidpath
#define AXIsProcessTrusted fake_AXIsProcessTrusted
#define AXUIElementCreateSystemWide fake_AXUIElementCreateSystemWide
#define AXUIElementCreateApplication fake_AXUIElementCreateApplication
#define AXUIElementSetMessagingTimeout fake_AXUIElementSetMessagingTimeout
#define AXUIElementCopyElementAtPosition fake_AXUIElementCopyElementAtPosition
#define AXUIElementGetPid fake_AXUIElementGetPid
#define AXUIElementCopyAttributeValue fake_AXUIElementCopyAttributeValue
#define AXUIElementSetAttributeValue fake_AXUIElementSetAttributeValue
#define AXUIElementPerformAction fake_AXUIElementPerformAction
#define CGEventTapCreate fake_CGEventTapCreate
#define CFMachPortIsValid fake_CFMachPortIsValid
#define CFMachPortInvalidate fake_CFMachPortInvalidate
#define CFMachPortCreateRunLoopSource fake_CFMachPortCreateRunLoopSource
#define CGEventTapIsEnabled fake_CGEventTapIsEnabled
#define CGEventTapEnable fake_CGEventTapEnable
#define main app_main
#include "main.m"
#undef main
#undef AXUIElementCreateApplication

static AXUIElementRef system_element, hit_element, window_element, app_element, other_window;
static CFMachPortRef tap_token;
static Context *tap_context;
static struct {
    double now, delay, timeout;
    AXUIElementRef prepared;
    int calls, preparations, fail_call, fail_preparation, overrun_call, writes;
    int tap_creations, tap_enables, tap_invalidations;
    bool finder, frontmost, same_window, trusted, tap_valid, tap_enabled;
    bool fail_enable, fail_create, fail_source;
    CFStringRef hit_role, top_role, subrole;
} fixture;

static void reset_fixture(void) {
    memset(&fixture, 0, sizeof(fixture));
    fixture.finder = fixture.trusted = true;
    fixture.delay = 0.001;
    fixture.hit_role = kAXButtonRole;
    fixture.top_role = kAXWindowRole;
    fixture.subrole = kAXStandardWindowSubrole;
}

static int fake_clock_gettime(clockid_t clock, struct timespec *time) {
    assert(clock == CLOCK_MONOTONIC);
    time->tv_sec = (time_t)fixture.now;
    time->tv_nsec = (long)((fixture.now - time->tv_sec) * 1e9);
    return 0;
}

static AXError begin_call(AXUIElementRef element) {
    assert(fixture.prepared == element);
    fixture.prepared = NULL;
    fixture.calls++;
    assert(fixture.timeout > 0 && fixture.timeout <= 0.025 - fixture.now + 1e-8);
    if (fixture.calls == fixture.overrun_call) {
        // A late OS response can exceed its timeout; the next call must not start.
        fixture.now += 0.030;
        return kAXErrorSuccess;
    }
    double elapsed = fmin(fixture.delay, fixture.timeout);
    fixture.now += elapsed;
    return fixture.calls == fixture.fail_call || elapsed < fixture.delay
        ? kAXErrorCannotComplete : kAXErrorSuccess;
}

static AXError fake_AXUIElementSetMessagingTimeout(AXUIElementRef element, float timeout) {
    fixture.preparations++;
    if (fixture.preparations == fixture.fail_preparation) return kAXErrorInvalidUIElement;
    fixture.prepared = element;
    fixture.timeout = timeout;
    return kAXErrorSuccess;
}

static AXError fake_AXUIElementCopyElementAtPosition(AXUIElementRef element, float x, float y,
                                                     AXUIElementRef *hit) {
    assert(element == system_element && x == -1200 && y == -200);
    AXError error = begin_call(element);
    if (error == kAXErrorSuccess) *hit = (AXUIElementRef)CFRetain(hit_element);
    return error;
}

static AXError fake_AXUIElementGetPid(AXUIElementRef element, pid_t *pid) {
    assert(element == hit_element);
    *pid = 101;
    return kAXErrorSuccess;
}

static int fake_proc_pidpath(int pid, void *buffer, uint32_t size) {
    assert(pid == 101);
    const char *path = fixture.finder
        ? "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder" : "/other/app";
    assert(strlen(path) + 1 <= size);
    strcpy(buffer, path);
    return (int)strlen(path);
}

static AXUIElementRef fake_AXUIElementCreateSystemWide(void) {
    return (AXUIElementRef)CFRetain(system_element);
}

static AXUIElementRef fake_AXUIElementCreateApplication(pid_t pid) {
    assert(pid == 101);
    return (AXUIElementRef)CFRetain(app_element);
}

static AXError fake_AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute,
                                                  CFTypeRef *value) {
    AXError error = begin_call(element);
    if (error != kAXErrorSuccess) return error;
    CFTypeRef result = NULL;
    if (CFEqual(attribute, kAXRoleAttribute))
        result = element == hit_element ? fixture.hit_role : fixture.top_role;
    else if (CFEqual(attribute, kAXTopLevelUIElementAttribute))
        result = window_element;
    else if (CFEqual(attribute, kAXSubroleAttribute))
        result = fixture.subrole;
    else if (CFEqual(attribute, kAXFrontmostAttribute))
        result = fixture.frontmost ? kCFBooleanTrue : kCFBooleanFalse;
    else if (CFEqual(attribute, kAXFocusedWindowAttribute))
        result = fixture.same_window ? window_element : other_window;
    else if (CFEqual(attribute, kAXWindowAttribute))
        result = window_element; // A sheet's AXWindow still points to its standard parent.
    assert(result);
    *value = CFRetain(result);
    return kAXErrorSuccess;
}

static AXError fake_AXUIElementSetAttributeValue(AXUIElementRef element, CFStringRef attribute,
                                                 CFTypeRef value) {
    assert(CFEqual(value, kCFBooleanTrue));
    assert(CFEqual(attribute, kAXMainAttribute) || CFEqual(attribute, kAXFrontmostAttribute));
    fixture.writes++;
    return begin_call(element);
}

static AXError fake_AXUIElementPerformAction(AXUIElementRef element, CFStringRef action) {
    assert(CFEqual(action, kAXRaiseAction));
    fixture.writes++;
    return begin_call(element);
}

static Boolean fake_AXIsProcessTrusted(void) { return fixture.trusted; }

static CFMachPortRef fake_CGEventTapCreate(CGEventTapLocation location, CGEventTapPlacement placement,
    CGEventTapOptions options, CGEventMask mask, CGEventTapCallBack callback, void *info) {
    assert(location == kCGSessionEventTap && placement == kCGHeadInsertEventTap);
    assert(options == kCGEventTapOptionDefault && mask == CGEventMaskBit(kCGEventLeftMouseDown));
    assert(callback == handle_event && info);
    tap_context = info;
    fixture.tap_creations++;
    if (fixture.fail_create) return NULL;
    tap_token = (CFMachPortRef)CFStringCreateWithFormat(NULL, NULL, CFSTR("tap-%d"), fixture.tap_creations);
    fixture.tap_valid = true;
    fixture.tap_enabled = false;
    return tap_token;
}

static Boolean fake_CFMachPortIsValid(CFMachPortRef tap) {
    assert(tap == tap_token);
    return fixture.tap_valid;
}

static void fake_CFMachPortInvalidate(CFMachPortRef tap) {
    assert(tap == tap_token);
    fixture.tap_invalidations++;
    fixture.tap_valid = fixture.tap_enabled = false;
}

static CFRunLoopSourceRef fake_CFMachPortCreateRunLoopSource(CFAllocatorRef allocator,
                                                            CFMachPortRef tap, CFIndex order) {
    assert(tap == tap_token);
    if (fixture.fail_source) return NULL;
    CFRunLoopSourceContext context = {0};
    return CFRunLoopSourceCreate(allocator, order, &context);
}

static bool fake_CGEventTapIsEnabled(CFMachPortRef tap) {
    assert(tap == tap_token);
    return fixture.tap_enabled;
}

static void fake_CGEventTapEnable(CFMachPortRef tap, bool enable) {
    assert(tap == tap_token && enable && fixture.tap_valid);
    fixture.tap_enables++;
    if (!fixture.fail_enable) fixture.tap_enabled = true;
}

@interface TestStatusItem : NSObject
@property(nonatomic, strong) NSButton *button;
@end
@implementation TestStatusItem
@end

static void check_status(AppDelegate *delegate, TestStatusItem *status, NSString *expected,
                         bool running) {
    NSMenuItem *state = [delegate valueForKey:@"stateItem"];
    NSMenuItem *permission = [delegate valueForKey:@"permissionItem"];
    NSTextField *label = [delegate valueForKey:@"stateLabel"];
    assert([state.title isEqualToString:expected]);
    assert([label.stringValue isEqualToString:expected]);
    assert(permission.hidden == running);
    assert(status.button.image == [delegate valueForKey:running ? @"normalImage" : @"inactiveImage"]);
    assert([status.button.toolTip isEqualToString:[@"Finder Click Fix — " stringByAppendingString:expected]]);
    assert([status.button.accessibilityValue isEqualToString:expected]);
}

static void check_event(CGEventRef event, CGEventType type) {
    Context context = {.system = system_element, .tap = tap_token};
    Context *event_context = type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput ? tap_context : &context;
    assert(handle_event(NULL, type, event, event_context) == event);
    assert(CGEventGetFlags(event) == (kCGEventFlagMaskShift | kCGEventFlagMaskCommand));
    assert(CGEventGetIntegerValueField(event, kCGMouseEventClickState) == 2);
    assert(CGPointEqualToPoint(CGEventGetLocation(event), CGPointMake(-1200, -200)));
}

static void test_focus(CGEventRef event) {
    reset_fixture();
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.writes == 3);
    int normal_calls = fixture.calls;
    for (int fail = 1; fail <= normal_calls; fail++) {
        reset_fixture();
        fixture.fail_call = fail;
        check_event(event, kCGEventLeftMouseDown);
        assert(fixture.calls == fail); // Includes partial main/frontmost/raise failures.
        reset_fixture();
        fixture.fail_preparation = fail;
        check_event(event, kCGEventLeftMouseDown);
        assert(fixture.calls == fail - 1 && fixture.preparations == fail);
    }
    reset_fixture();
    fixture.delay = 0.008;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.calls == 4 && fixture.writes == 0 && fixture.now <= 0.025 + 1e-8);
    reset_fixture();
    fixture.overrun_call = 1;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.calls == 1 && fixture.preparations == 1 && fixture.writes == 0);

    CFStringRef excluded_roles[] = {kAXSheetRole, kAXDrawerRole};
    for (size_t i = 0; i < sizeof(excluded_roles) / sizeof(excluded_roles[0]); i++) {
        reset_fixture();
        fixture.top_role = excluded_roles[i];
        check_event(event, kCGEventLeftMouseDown);
        assert(fixture.writes == 0);
        reset_fixture();
        fixture.hit_role = excluded_roles[i];
        check_event(event, kCGEventLeftMouseDown);
        assert(fixture.writes == 0);
    }
    CFStringRef excluded_subroles[] = {kAXDialogSubrole, kAXUnknownSubrole};
    for (size_t i = 0; i < sizeof(excluded_subroles) / sizeof(excluded_subroles[0]); i++) {
        reset_fixture();
        fixture.subrole = excluded_subroles[i];
        check_event(event, kCGEventLeftMouseDown);
        assert(fixture.writes == 0);
    }
    reset_fixture();
    fixture.hit_role = kAXWindowRole;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.writes == 3); // Clicking the window itself still works.
    reset_fixture();
    fixture.frontmost = fixture.same_window = true;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.writes == 0);
    reset_fixture();
    fixture.frontmost = true;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.writes == 3); // Another Finder window needs correction.
    reset_fixture();
    fixture.finder = false;
    fixture.delay = 0.100;
    check_event(event, kCGEventLeftMouseDown);
    assert(fixture.calls == 1 && fixture.writes == 0 && fixture.now <= 0.025 + 1e-8);
    reset_fixture();
    check_event(event, kCGEventLeftMouseDragged);
    check_event(event, kCGEventLeftMouseUp);
    assert(fixture.calls == 0);
}

static void test_tap(CGEventRef event) {
    reset_fixture();
    AppDelegate *delegate = [[AppDelegate alloc] initWithVerbose:false];
    NSMenu *menu = [delegate makeMenu];
    TestStatusItem *status = [[TestStatusItem alloc] init];
    status.button = [[NSButton alloc] initWithFrame:NSZeroRect];
    NSImage *normal = [[NSImage alloc] initWithContentsOfFile:@"assets/StatusIcon@2x.png"];
    assert(normal);
    normal.size = NSMakeSize(18, 18);
    normal.template = YES;
    NSImage *inactive = inactive_icon(normal);
    assert(inactive && ![normal.TIFFRepresentation isEqualToData:inactive.TIFFRepresentation]);
    [delegate setValue:status forKey:@"statusItem"];
    [delegate setValue:normal forKey:@"normalImage"];
    [delegate setValue:inactive forKey:@"inactiveImage"];
    fixture.trusted = false;
    [delegate startFix];
    assert(fixture.tap_creations == 0);
    check_status(delegate, status, @"Inactive: Accessibility required", false);
    fixture.trusted = true;
    [delegate startFix];
    check_status(delegate, status, @"Active", true);
    [delegate menuWillOpen:menu];
    assert(fixture.tap_creations == 1 && fixture.tap_enables == 1);
    fixture.tap_enabled = false;
    [delegate menuWillOpen:menu];
    assert(fixture.tap_enables == 2);
    check_status(delegate, status, @"Active", true);
    CGEventType disabled_types[] = {kCGEventTapDisabledByTimeout, kCGEventTapDisabledByUserInput};
    for (size_t i = 0; i < sizeof(disabled_types) / sizeof(disabled_types[0]); i++) {
        fixture.tap_enabled = false;
        fixture.fail_enable = true;
        check_event(event, disabled_types[i]);
        // Check immediately after the notification, before any menu interaction.
        check_status(delegate, status, @"Inactive: Mouse input unavailable", false);
        [delegate menuWillOpen:menu];
        check_status(delegate, status, @"Inactive: Mouse input unavailable", false);
        fixture.fail_enable = false;
        check_event(event, disabled_types[i]);
        assert(fixture.tap_enabled);
        check_status(delegate, status, @"Active", true);
    }
    fixture.tap_valid = false;
    int enables = fixture.tap_enables;
    check_event(event, kCGEventTapDisabledByTimeout);
    assert(fixture.tap_enables == enables);
    check_status(delegate, status, @"Inactive: Mouse input unavailable", false);
    [delegate menuWillOpen:menu];
    assert(fixture.tap_creations == 2 && fixture.tap_invalidations == 1);
    check_status(delegate, status, @"Active", true);
    fixture.trusted = false;
    // An enabled tap alone must never display Active without AX permission.
    [delegate updateStatus];
    assert(fixture.tap_enabled);
    check_status(delegate, status, @"Inactive: Accessibility required", false);
    [delegate menuWillOpen:menu];
    check_status(delegate, status, @"Inactive: Accessibility required", false);
    fixture.trusted = true;
    [delegate menuWillOpen:menu];
    assert(fixture.tap_creations == 3);
    check_status(delegate, status, @"Active", true);
    [delegate stopFix];
    for (int failure = 0; failure < 3; failure++) {
        reset_fixture();
        fixture.fail_create = failure == 0;
        fixture.fail_source = failure == 1;
        fixture.fail_enable = failure == 2;
        [delegate startFix];
        check_status(delegate, status, @"Inactive: Mouse input unavailable", false);
        fixture.fail_create = fixture.fail_source = fixture.fail_enable = false;
        [delegate menuWillOpen:menu];
        check_status(delegate, status, @"Active", true);
        [delegate stopFix];
    }
}

int main(void) {
    @autoreleasepool {
        system_element = AXUIElementCreateApplication(100);
        hit_element = AXUIElementCreateApplication(101);
        window_element = AXUIElementCreateApplication(102);
        app_element = AXUIElementCreateApplication(103);
        other_window = AXUIElementCreateApplication(104);
        CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown,
            CGPointMake(-1200, -200), kCGMouseButtonLeft);
        assert(event);
        CGEventSetFlags(event, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, 2);
        test_focus(event);
        test_tap(event);
        CFRelease(event);
        CFRelease(other_window);
        CFRelease(app_element);
        CFRelease(window_element);
        CFRelease(hit_element);
        CFRelease(system_element);
        puts("PASS: AX budget, sheets/dialogs, partial failures, event preservation, tap recovery/status/icon");
    }
    return 0;
}
