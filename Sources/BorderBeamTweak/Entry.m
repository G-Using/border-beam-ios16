//
//  Entry.m
//  BorderBeamTweak
//
//  Two independent ways to get called when the image loads:
//
//    1. a C constructor (`__mod_init_func`), and
//    2. `+load` on an ObjC class.
//
//  Whichever fires first wins; `dispatch_once` makes the second a no-op.
//
//  v1.0 relied on a constructor alone, and the Release build dead-stripped it:
//  the dylib loaded, nothing ran, and the tweak looked completely dead. The
//  constructor is therefore non-static + `used`, and the target builds with
//  DEAD_CODE_STRIPPING = NO.
//
#import <Foundation/Foundation.h>

extern void borderBeam_init(void);

static void borderbeam_install_once(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        borderBeam_init();
    });
}

__attribute__((constructor, used, visibility("default")))
void borderbeam_ctor(void) {
    borderbeam_install_once();
}

@interface BorderBeamLoader : NSObject
@end

@implementation BorderBeamLoader

+ (void)load {
    borderbeam_install_once();
}

@end
