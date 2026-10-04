#import <AppKit/AppKit.h>

static NSImage *mark(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [color setFill];
        NSBezierPath *window = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 16, 16)
            xRadius:4 yRadius:4];

        NSBezierPath *pointer = [NSBezierPath bezierPath];
        [pointer moveToPoint:NSMakePoint(6.1, 12.8)];
        [pointer curveToPoint:NSMakePoint(5.7, 12.4)
            controlPoint1:NSMakePoint(5.85, 12.95) controlPoint2:NSMakePoint(5.7, 12.7)];
        [pointer lineToPoint:NSMakePoint(5.7, 6.0)];
        [pointer curveToPoint:NSMakePoint(6.5, 5.6)
            controlPoint1:NSMakePoint(5.7, 5.55) controlPoint2:NSMakePoint(6.1, 5.4)];
        [pointer lineToPoint:NSMakePoint(7.6, 6.45)];
        [pointer curveToPoint:NSMakePoint(8.15, 6.35)
            controlPoint1:NSMakePoint(7.83, 6.64) controlPoint2:NSMakePoint(8.0, 6.61)];
        [pointer lineToPoint:NSMakePoint(9.3, 4.5)];
        [pointer curveToPoint:NSMakePoint(10.1, 4.3)
            controlPoint1:NSMakePoint(9.45, 4.22) controlPoint2:NSMakePoint(9.8, 4.12)];
        [pointer lineToPoint:NSMakePoint(11.0, 4.9)];
        [pointer curveToPoint:NSMakePoint(11.2, 5.7)
            controlPoint1:NSMakePoint(11.27, 5.1) controlPoint2:NSMakePoint(11.39, 5.4)];
        [pointer lineToPoint:NSMakePoint(10.05, 7.65)];
        [pointer curveToPoint:NSMakePoint(10.36, 8.03)
            controlPoint1:NSMakePoint(9.91, 7.86) controlPoint2:NSMakePoint(10.05, 8.02)];
        [pointer lineToPoint:NSMakePoint(12.3, 8.2)];
        [pointer curveToPoint:NSMakePoint(12.5, 9.0)
            controlPoint1:NSMakePoint(12.77, 8.25) controlPoint2:NSMakePoint(12.92, 8.75)];
        [pointer lineToPoint:NSMakePoint(6.55, 12.7)];
        [pointer curveToPoint:NSMakePoint(6.1, 12.8)
            controlPoint1:NSMakePoint(6.4, 12.82) controlPoint2:NSMakePoint(6.25, 12.85)];
        [pointer closePath];
        NSAffineTransform *offset = [NSAffineTransform transform];
        NSRect bounds = pointer.bounds;
        [offset translateXBy:NSMidX(bounds) + 0.6 yBy:NSMidY(bounds) + 0.6];
        [offset scaleBy:2.0 / 3.0];
        [offset translateXBy:-NSMidX(bounds) yBy:-NSMidY(bounds)];
        [pointer transformUsingAffineTransform:offset];
        window.windingRule = NSWindingRuleEvenOdd;
        [window appendBezierPath:pointer];
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
