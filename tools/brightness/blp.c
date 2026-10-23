// blp <param> [value] — 读写 AppleBacklightDisplay 的任意亮度参数
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: blp <brightness|linear-brightness> [value]\n"); return 1; }
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleBacklightDisplay"));
    if (!svc) { fprintf(stderr, "no AppleBacklightDisplay\n"); return 2; }
    CFStringRef key = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    float v = 0;
    if (argc == 2) {
        if (IODisplayGetFloatParameter(svc, 0, key, &v) != kIOReturnSuccess) { fprintf(stderr, "get failed\n"); return 3; }
        printf("%s = %.4f\n", argv[1], v);
    } else {
        v = (float)atof(argv[2]);
        kern_return_t kr = IODisplaySetFloatParameter(svc, 0, key, v);
        if (kr != kIOReturnSuccess) { fprintf(stderr, "set failed 0x%x\n", kr); return 4; }
        printf("set %s = %.4f\n", argv[1], v);
    }
    IOObjectRelease(svc);
    return 0;
}
