// bl — 读写 AppleBacklightDisplay 亮度 (0..1)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static io_service_t backlight(void) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault,
                         IOServiceMatching("AppleBacklightDisplay"));
    return s;
}

int main(int argc, char **argv) {
    io_service_t svc = backlight();
    if (!svc) { fprintf(stderr, "no AppleBacklightDisplay\n"); return 2; }
    float v = 0;
    if (argc == 1) {
        if (IODisplayGetFloatParameter(svc, 0, CFSTR("linear-brightness"), &v) != kIOReturnSuccess) {
            fprintf(stderr, "get failed\n"); return 3;
        }
        printf("%.4f\n", v);
        IOObjectRelease(svc);
        return 0;
    }
    v = (float)atof(argv[1]);
    if (v < 0) v = 0; if (v > 1) v = 1;
    kern_return_t kr = IODisplaySetFloatParameter(svc, 0, CFSTR("linear-brightness"), v);
    IOObjectRelease(svc);
    if (kr != kIOReturnSuccess) { fprintf(stderr, "set failed 0x%x\n", kr); return 4; }
    printf("ok %.4f\n", v);
    return 0;
}
