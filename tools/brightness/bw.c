// bw — 亮度看门狗（常驻，零 fork）
//  启动时应用保存值；检测"亮度被系统重置为 100%"时恢复；检测用户改动时保存。
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define STATE "/Users/Shared/brightness.level"
#define TICK_MS 300
#define GAP_S  2.0

typedef int (*get_fn)(CGDirectDisplayID, float *);
typedef int (*set_fn)(CGDirectDisplayID, float);
static get_fn ds_get;
static set_fn ds_set;

static double wall(void) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

static int read_state(float *v) {
    FILE *f = fopen(STATE, "r");
    if (!f) return 0;
    float x = -1;
    if (fscanf(f, "%f", &x) != 1) { fclose(f); return 0; }
    fclose(f);
    if (x < 0 || x > 1) return 0;
    *v = x;
    return 1;
}

static void write_state(float v) {
    char tmp[256]; snprintf(tmp, sizeof tmp, STATE ".tmp");
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fprintf(f, "%.4f\n", v);
    fclose(f);
    rename(tmp, STATE);
}

// 直接读 IODisplayWrangler 的当前电源状态（不 fork，微秒级）
static int display_power_state(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                          IOServiceMatching("IODisplayWrangler"));
    if (!svc) return -1;
    int state = -1;
    CFTypeRef pm = IORegistryEntryCreateCFProperty(svc, CFSTR("IOPowerManagement"),
                                                   kCFAllocatorDefault, 0);
    if (pm && CFGetTypeID(pm) == CFDictionaryGetTypeID()) {
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue((CFDictionaryRef)pm,
                                                          CFSTR("CurrentPowerState"));
        if (n && CFGetTypeID(n) == CFNumberGetTypeID()) {
            int v = -1;
            if (CFNumberGetValue(n, kCFNumberIntType, &v)) state = v;
        }
    }
    if (pm) CFRelease(pm);
    IOObjectRelease(svc);
    return state;
}

static int get_brightness(float *v) { return ds_get(CGMainDisplayID(), v) == 0; }
static int set_brightness(float v)  { return ds_set(CGMainDisplayID(), v) == 0; }

int main(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed\n"); return 2; }
    ds_get = (get_fn)dlsym(h, "DisplayServicesGetBrightness");
    ds_set = (set_fn)dlsym(h, "DisplayServicesSetBrightness");
    if (!ds_get || !ds_set) { fprintf(stderr, "symbols missing\n"); return 3; }

    float saved;
    if (!read_state(&saved)) { fprintf(stderr, "no state\n"); return 4; }

    float v;
    if (!get_brightness(&v)) { fprintf(stderr, "display not ready\n"); }

    set_brightness(saved);              // 启动即同步
    float prev = saved;
    int prev_state = display_power_state();
    double last = wall();

    for (;;) {
        struct timespec ts = { 0, TICK_MS * 1000000L };
        nanosleep(&ts, NULL);

        double t = wall();
        if (t - last > GAP_S) {         // 整机睡眠后恢复
            set_brightness(saved);
            last = t; prev = saved;
            continue;
        }
        last = t;

        // 显示器 非4 → 4：面板被重置，重新应用
        int st = display_power_state();
        if (st == 4 && prev_state != 4 && prev_state >= 0) {
            set_brightness(saved);
            prev_state = st; prev = saved;
            continue;
        }
        prev_state = st;

        if (!get_brightness(&v)) continue;

        // 系统把亮度重置成 100%，而保存值不是 100%，且是突变 → 恢复
        if (saved < 0.999f && v > 0.999f && prev > 0.99f * saved) {
            set_brightness(saved);
            prev = saved;
            continue;
        }
        // 用户改动 → 保存
        if (v != saved && v <= 0.999f) {
            saved = v;
            write_state(v);
        }
        prev = v;
    }
    return 0;
}
