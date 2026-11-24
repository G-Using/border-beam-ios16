//
//  Entry.c
//  BorderBeamTweak
//
//  A plain C constructor so the dylib starts without pulling in the Swift
//  runtime first. Everything real lives in Swift, called on demand.
//
extern void borderBeam_init(void);

__attribute__((constructor))
static void borderbeam_ctor(void) {
    borderBeam_init();
}
