#import <AppKit/AppKit.h>

static NSImage *mark(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [color setFill];
        NSBezierPath *window = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 16, 16)
            xRadius:4 yRadius:4];
        NSBezierPath *header = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5, 13, 11, 1.2)
            xRadius:0.6 yRadius:0.6];
        window.windingRule = NSWindingRuleEvenOdd;
        [window appendBezierPath:header];
        [window appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.3, 3.8, 7.4, 7.4)]];
        [window appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.1, 4.6, 5.8, 5.8)]];
        [window appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.1, 5.6, 3.8, 3.8)]];
        [window appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.9, 6.4, 2.2, 2.2)]];
        [window fill];
        return YES;
    }];
}

static void writePNG(NSImage *image, NSInteger size, NSString *path) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [image drawInRect:NSMakeRect(0, 0, size, size)];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:path atomically:YES]) {
        fprintf(stderr, "Cannot write icon: %s\n", path.fileSystemRepresentation);
        exit(1);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    @autoreleasepool {
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSString *iconset = [directory stringByAppendingPathComponent:@"AppIcon.iconset"];
        [NSFileManager.defaultManager createDirectoryAtPath:iconset
            withIntermediateDirectories:YES attributes:nil error:NULL];
        NSImage *status = mark(NSColor.blackColor);
        writePNG(status, 18, [directory stringByAppendingPathComponent:@"StatusIcon.png"]);
        writePNG(status, 36, [directory stringByAppendingPathComponent:@"StatusIcon@2x.png"]);
        NSImage *loadedStatus = [[NSImage alloc] initWithContentsOfFile:
            [directory stringByAppendingPathComponent:@"StatusIcon@2x.png"]];
        writePNG(status, 144, [directory stringByAppendingPathComponent:@"StatusIcon-preview.png"]);
        NSImage *whiteMark = mark(NSColor.whiteColor);
        NSImage *contrastPreview = [NSImage imageWithSize:NSMakeSize(96, 96) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            (void)rect;
            [NSColor.whiteColor setFill];
            NSRectFill(NSMakeRect(0, 48, 96, 48));
            [[NSColor colorWithWhite:0.17 alpha:1] setFill];
            NSRectFill(NSMakeRect(0, 0, 96, 48));
            [loadedStatus drawInRect:NSMakeRect(39, 63, 18, 18)];
            [whiteMark drawInRect:NSMakeRect(39, 15, 18, 18)];
            return YES;
        }];
        writePNG(contrastPreview, 192, [directory stringByAppendingPathComponent:@"StatusIcon-contrast-preview.png"]);
        NSImage *appIcon = [NSImage imageWithSize:NSMakeSize(1024, 1024) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            (void)rect;
            NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(72, 72, 880, 880)
                xRadius:192 yRadius:192];
            NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:
                [NSColor colorWithWhite:0.12 alpha:1] endingColor:[NSColor colorWithWhite:0.23 alpha:1]];
            [gradient drawInBezierPath:tile angle:90];
            [whiteMark drawInRect:NSMakeRect(96, 96, 832, 832)];
            return YES;
        }];
        for (NSNumber *value in @[@16, @32, @128, @256, @512]) {
            NSInteger size = value.integerValue;
            writePNG(appIcon, size, [iconset stringByAppendingPathComponent:
                [NSString stringWithFormat:@"icon_%ldx%ld.png", (long)size, (long)size]]);
            writePNG(appIcon, size * 2, [iconset stringByAppendingPathComponent:
                [NSString stringWithFormat:@"icon_%ldx%ld@2x.png", (long)size, (long)size]]);
        }
        writePNG(appIcon, 512, [directory stringByAppendingPathComponent:@"AppIcon-preview.png"]);
    }
    return 0;
}
