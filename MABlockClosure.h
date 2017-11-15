
#import <Foundation/Foundation.h>


#if (TARGET_OS_IPHONE && TARGET_OS_EMBEDDED) || TARGET_IPHONE_SIMULATOR
#define USE_CUSTOM_LIBFFI 1
#endif

#if USE_CUSTOM_LIBFFI
#import "ffi.h"
#define USE_LIBFFI_CLOSURE_ALLOC 1
#else // use system libffi
#import <ffi/ffi.h>
#endif


@interface MABlockClosure : NSObject
{
    NSMutableArray *_allocations;
    ffi_cif _closureCIF;
    ffi_cif _innerCIF;
    int _closureArgCount;
    ffi_closure *_closure;
    void *_closureFptr;
    id _block;
    NSString * _signature;
}

- (id)initWithBlock: (id)block;
- (id)initWithSignature: (NSString *)signature;
- (void *)fptr;
- (void)returnValue:(void *)returnValue callWithArguments:(NSArray *)arguments funtion:(void *)afunction;
@end

#ifdef __cplusplus
extern "C" {
#endif /// __cplusplus

// convenience function, returns a function pointer
// whose lifetime is tied to 'block'
// block MUST BE a heap block (pre-copied)
// or a global block
void *BlockFptr(id block);

// copies/autoreleases the block, then returns
// function pointer associated to it
void *BlockFptrAuto(id block);
    
    

#ifdef __cplusplus
}
#endif /// __cplusplus
