
#import "MABlockClosure.h"

#import <assert.h>
#import <objc/runtime.h>
#import <sys/mman.h>

#if TARGET_OS_IPHONE
#import <CoreGraphics/CoreGraphics.h>
#endif


@implementation MABlockClosure

struct BlockDescriptor
{
    unsigned long reserved;
    unsigned long size;
    void *rest[1];
};

struct Block
{
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    struct BlockDescriptor *descriptor;
};
    

static void *BlockImpl(id block)
{
    return ((struct Block *)block)->invoke;
}

static const char *FunctionSig(id blockObj)
{
    if ([blockObj isKindOfClass:NSString.class]) {
        NSString *sign = blockObj;
        return [sign UTF8String];
    }
    
    
    struct Block *block = (void *)blockObj;
    struct BlockDescriptor *descriptor = block->descriptor;
    
    int copyDisposeFlag = 1 << 25;
    int signatureFlag = 1 << 30;
    
    assert(block->flags & signatureFlag);
    
    int index = 0;
    if(block->flags & copyDisposeFlag)
        index += 2;
    
    return descriptor->rest[index];
}

static void BlockClosure(ffi_cif *cif, void *ret, void **args, void *userdata)
{
    MABlockClosure *self = userdata;
    if (self->_signature.length > 0 ) {
        const char *str = [self->_signature UTF8String];
        int i = -1;
        while(str && *str)
        {
            const char *next = SizeAndAlignment(str, NULL, NULL, NULL);
            if(i >= 0)
                [self _ffiValueForEncode:str argumentPtr:args[i]];
            i++;
            str = next;
        }
        
        //!!!!!!!!这里先写死，后面根据返回值的描述进一步写返回值的类型
        *(CGRect *)ret = CGRectMake(321, 123, 10, 10);
    }
    if (self->_block) {
        int count = self->_closureArgCount;
        void **innerArgs = malloc((count + 1) * sizeof(*innerArgs));
        innerArgs[0] = &self->_block;
        memcpy(innerArgs + 1, args, count * sizeof(*args));
        ffi_call(&self->_innerCIF, BlockImpl(self->_block), ret, innerArgs);
        free(innerArgs);
    }
}

static void *AllocateClosure(void **codePtr)
{
#if USE_LIBFFI_CLOSURE_ALLOC
    return ffi_closure_alloc(sizeof(ffi_closure), codePtr);
#else
    ffi_closure *closure = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if(closure == (void *)-1)
    {
        perror("mmap");
        return NULL;
    }
    *codePtr = closure;
    return closure;
#endif
}

static void DeallocateClosure(void *closure)
{
#if USE_LIBFFI_CLOSURE_ALLOC
    ffi_closure_free(closure);
#else
    munmap(closure, sizeof(ffi_closure));
#endif
}

- (void *)_allocate: (size_t)howmuch
{
    NSMutableData *data = [NSMutableData dataWithLength: howmuch];
    [_allocations addObject: data];
    return [data mutableBytes];
}

static const char *SizeAndAlignment(const char *str, NSUInteger *sizep, NSUInteger *alignp, int *len)
{
    const char *out = NSGetSizeAndAlignment(str, sizep, alignp);
    if(len)
        *len = out - str;
    while(isdigit(*out))
        out++;
    return out;
}

static int ArgCount(const char *str)
{
    int argcount = -1; // return type is the first one
    while(str && *str)
    {
        str = SizeAndAlignment(str, NULL, NULL, NULL);
        argcount++;
    }
    return argcount;
}

- (ffi_type *)_ffiArgForEncode: (const char *)str
{
    #define SINT(type) do { \
    	if(str[0] == @encode(type)[0]) \
    	{ \
    	   if(sizeof(type) == 1) \
    	       return &ffi_type_sint8; \
    	   else if(sizeof(type) == 2) \
    	       return &ffi_type_sint16; \
    	   else if(sizeof(type) == 4) \
    	       return &ffi_type_sint32; \
    	   else if(sizeof(type) == 8) \
    	       return &ffi_type_sint64; \
    	   else \
    	   { \
    	       NSLog(@"Unknown size for type %s", #type); \
    	       abort(); \
    	   } \
        } \
    } while(0)
    
    #define UINT(type) do { \
    	if(str[0] == @encode(type)[0]) \
    	{ \
    	   if(sizeof(type) == 1) \
    	       return &ffi_type_uint8; \
    	   else if(sizeof(type) == 2) \
    	       return &ffi_type_uint16; \
    	   else if(sizeof(type) == 4) \
    	       return &ffi_type_uint32; \
    	   else if(sizeof(type) == 8) \
    	       return &ffi_type_uint64; \
    	   else \
    	   { \
    	       NSLog(@"Unknown size for type %s", #type); \
    	       abort(); \
    	   } \
        } \
    } while(0)
    
    #define INT(type) do { \
        SINT(type); \
        UINT(unsigned type); \
    } while(0)
    
    #define COND(type, name) do { \
        if(str[0] == @encode(type)[0]) \
            return &ffi_type_ ## name; \
    } while(0)
    
    #define PTR(type) COND(type, pointer)
    
    #define STRUCT(structType, ...) do { \
        if(strncmp(str, @encode(structType), strlen(@encode(structType))) == 0) \
        { \
           ffi_type *elementsLocal[] = { __VA_ARGS__, NULL }; \
           ffi_type **elements = [self _allocate: sizeof(elementsLocal)]; \
           memcpy(elements, elementsLocal, sizeof(elementsLocal)); \
            \
           ffi_type *structType = [self _allocate: sizeof(*structType)]; \
           structType->type = FFI_TYPE_STRUCT; \
           structType->elements = elements; \
           return structType; \
        } \
    } while(0)
    
    SINT(_Bool);
    SINT(signed char);
    UINT(unsigned char);
    INT(short);
    INT(int);
    INT(long);
    INT(long long);
    
    PTR(id);
    PTR(Class);
    PTR(SEL);
    PTR(void *);
    PTR(char *);
    PTR(void (*)(void));
    
    COND(float, float);
    COND(double, double);
    
    COND(void, void);
    
    ffi_type *CGFloatFFI = sizeof(CGFloat) == sizeof(float) ? &ffi_type_float : &ffi_type_double;
    STRUCT(CGRect, CGFloatFFI, CGFloatFFI, CGFloatFFI, CGFloatFFI);
    STRUCT(CGPoint, CGFloatFFI, CGFloatFFI);
    STRUCT(CGSize, CGFloatFFI, CGFloatFFI);
    
#if !TARGET_OS_IPHONE
    STRUCT(NSRect, CGFloatFFI, CGFloatFFI, CGFloatFFI, CGFloatFFI);
    STRUCT(NSPoint, CGFloatFFI, CGFloatFFI);
    STRUCT(NSSize, CGFloatFFI, CGFloatFFI);
#endif
    
    NSLog(@"Unknown encode string %s", str);
    abort();
}

- (void *)_ffiValueForEncode: (const char *)str argumentPtr:(void**)argumentPtr
{
#define JP_BLOCK_PARAM_CASE(_typeString, _type, _selector) \
case _typeString: {                              \
_type returnValue = *(_type *)argumentPtr;                     \
param = [NSNumber _selector:returnValue];\
break; \
}
    
#define SINTV(_type,_selector) do { \
if(str[0] == @encode(_type)[0]) \
{ \
_type returnValue = *(_type *)argumentPtr; \
NSLog(@"参数值是%@",[NSNumber _selector:returnValue]);\
return [NSNumber _selector:returnValue]; \
} \
} while(0)

#define STRUCV(_type) do { \
if(strncmp(str, @encode(_type), strlen(@encode(_type))) == 0) \
{ \
_type returnValue = *(_type *)argumentPtr; \
NSLog(@"参数值是%@",NSStringFrom##_type(returnValue));\
return (NSString *)NSStringFrom##_type(returnValue); \
} \
} while(0)
    
#define PTROC(type) do { \
if(str[0] == @encode(type)[0]) \
{\
NSLog(@"OC对象参数值是%@",(__bridge id)(*(void**)argumentPtr));\
return (__bridge id)(*(void**)argumentPtr); \
}\
} while(0)


    

#define PTRC(type) do { \
if(str[0] == @encode(type)[0]) \
{\
NSLog(@"C指针地址是%p",*argumentPtr);\
return *argumentPtr; \
}\
} while(0)
    
    
    SINTV(_Bool, numberWithBool);
    SINTV(signed char, numberWithChar);
    SINTV(unsigned char, numberWithUnsignedChar);
    SINTV(short, numberWithShort);
    SINTV(int, numberWithInt);
    SINTV(long, numberWithLong);
    SINTV(long long, numberWithLongLong);
    
    PTROC(id);
    PTROC(Class);

    if(str[0] == @encode(SEL)[0]) {
        SEL returnValue = *(SEL *)argumentPtr;
        NSLog(@"OC对象参数值是%@",NSStringFromSelector(returnValue));\
        return NSStringFromSelector(returnValue); \
    }

//    if(strncmp(str, @encode(CGRect), strlen(@encode(CGRect))) == 0) {
//        CGRect rect = (CGRect)(* (CGRect*)argumentPtr);
//        NSLog(@"%@", NSStringFromCGRect(rect));
//    }
    
    PTRC(void *);
    PTRC(char *);
    PTRC(void (*)(void));
    
    SINTV(float, numberWithFloat);
    SINTV(double, numberWithDouble);
    STRUCV(CGRect);
    STRUCV(CGPoint);
    STRUCV(CGSize);
    return (void *)0;
}


- (ffi_type **)_argsWithEncodeString: (const char *)str getCount: (int *)outCount
{
    int argCount = ArgCount(str);
    ffi_type **argTypes = [self _allocate: argCount * sizeof(*argTypes)];
    
    int i = -1;
    while(str && *str)
    {
        const char *next = SizeAndAlignment(str, NULL, NULL, NULL);
        if(i >= 0)
            argTypes[i] = [self _ffiArgForEncode: str];
        i++;
        str = next;
    }
    
    *outCount = argCount;
    
    return argTypes;
}

- (int)_prepCIF: (ffi_cif *)cif withEncodeString: (const char *)str skipArg: (BOOL)skip
{
    NSLog(@"block sign is %@", @(str));
    int argCount;
    ffi_type **argTypes = [self _argsWithEncodeString: str getCount: &argCount];
    
    if(skip)
    {
        argTypes++;
        argCount--;
    }
    
    ffi_status status = ffi_prep_cif(cif, FFI_DEFAULT_ABI, argCount, [self _ffiArgForEncode: str], argTypes);
    if(status != FFI_OK)
    {
        NSLog(@"Got result %ld from ffi_prep_cif", (long)status);
        abort();
    }
    
    return argCount;
}

- (void)_prepClosureCIF
{
    _closureArgCount = [self _prepCIF: &_closureCIF withEncodeString: FunctionSig(_block?:_signature) skipArg: _block?YES:NO];
}

- (void)_prepInnerCIF
{
    [self _prepCIF: &_innerCIF withEncodeString: FunctionSig(_block?:_signature) skipArg: NO];
}

- (void)_prepClosure
{
#if USE_LIBFFI_CLOSURE_ALLOC
    ffi_status status = ffi_prep_closure_loc(_closure, &_closureCIF, BlockClosure, self, _closureFptr);
    if(status != FFI_OK)
    {
        NSLog(@"ffi_prep_closure returned %d", (int)status);
        abort();
    }
#else
    ffi_status status = ffi_prep_closure(_closure, &_closureCIF, BlockClosure, self);
    if(status != FFI_OK)
    {
        NSLog(@"ffi_prep_closure returned %d", (int)status);
        abort();
    }
    
    if(mprotect(_closure, sizeof(_closure), PROT_READ | PROT_EXEC) == -1)
    {
        perror("mprotect");
        abort();
    }
#endif
}

- (id)initWithBlock: (id)block
{
    if((self = [self init]))
    {
        _allocations = [[NSMutableArray alloc] init];
        _block = block;
        _closure = AllocateClosure(&_closureFptr);
        [self _prepClosureCIF];
        [self _prepInnerCIF];
        [self _prepClosure];
    }
    return self;
}

- (id)initWithSignature: (NSString *)signature {
    _allocations = [[NSMutableArray alloc] init];
    _signature = signature;
    _closure = AllocateClosure(&_closureFptr);
    [self _prepClosureCIF];
    [self _prepClosure];
    return self;
}

- (void)dealloc
{
    if(_closure)
        DeallocateClosure(_closure);
    [_allocations release];
    [super dealloc];
}

- (void *)fptr
{
    return _closureFptr;
}

@end

void *BlockFptr(id block)
{
    @synchronized(block)
    {
        MABlockClosure *closure = objc_getAssociatedObject(block, BlockFptr);
        if(!closure)
        {
            closure = [[MABlockClosure alloc] initWithBlock: block];
            objc_setAssociatedObject(block, BlockFptr, closure, OBJC_ASSOCIATION_RETAIN);
            [closure release]; // retained by the associated object assignment
        }
        return [closure fptr];
    }
}

void *BlockFptrAuto(id block)
{
    return BlockFptr([[block copy] autorelease]);
}
