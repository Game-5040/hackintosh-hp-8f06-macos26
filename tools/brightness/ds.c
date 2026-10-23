// ds — 通过 DisplayServices 私有接口读写亮度（和控制中心同一条路）
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*get_fn)(CGDirectDisplayID, float *);
typedef int (*set_fn)(CGDirectDisplayID, float);

int main(int argc, char **argv) {
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 2; }
    get_fn  get = (get_fn)dlsym(h, "DisplayServicesGetBrightness");
    set_fn  set = (set_fn)dlsym(h, "DisplayServicesSetBrightness");
    if (!get || !set) { fprintf(stderr, "symbols not found (get=%p set=%p)\n", (void*)get, (void*)set); return 3; }
    CGDirectDisplayID d = CGMainDisplayID();
    float v = -1;
    int kr = get(d, &v);
    if (argc == 1) { printf("%.4f\n", v); return 0; }
    float want = (float)atof(argv[1]);
    kr = set(d, want);
    get(d, &v);
    printf("ok %.4f\n", v);
    return 0;
}
