#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
int main(void) {
    CGDirectDisplayID d = CGMainDisplayID();
    const void *keys[] = { kCGDisplayShowDuplicateLowResolutionModes };
    const void *vals[] = { kCFBooleanTrue };
    CFDictionaryRef opts = CFDictionaryCreate(NULL, keys, vals, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef arr = CGDisplayCopyAllDisplayModes(d, opts);
    if (!arr) { printf("no modes\n"); return 1; }
    long n = CFArrayGetCount(arr), hi = 0;
    printf("总模式: %ld\n", n);
    for (long i = 0; i < n; i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(arr, i);
        size_t w = CGDisplayModeGetWidth(m), h = CGDisplayModeGetHeight(m);
        size_t pw = CGDisplayModeGetPixelWidth(m), ph = CGDisplayModeGetPixelHeight(m);
        if (pw > w) { hi++; printf("  HiDPI %zux%zu (像素 %zux%zu)\n", w, h, pw, ph); }
    }
    printf("HiDPI 数量: %ld\n", hi);
    CFRelease(arr); CFRelease(opts);
    return 0;
}
