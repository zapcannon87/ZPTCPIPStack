#ifndef LWIP_ARCH_CC_H
#define LWIP_ARCH_CC_H

#if defined(__aarch64__)
#include <arm/endian.h>
#else /* __aarch64__ */
//#ifndef LITTLE_ENDIAN
//#define LITTLE_ENDIAN 1234
//#endif /* LITTLE_ENDIAN */
//#ifndef BIG_ENDIAN
//#define BIG_ENDIAN 4321
//#endif /* BIG_ENDIAN */
//#ifndef BYTE_ORDER
//#define BYTE_ORDER LITTLE_ENDIAN
//#endif /* BYTE_ORDER */
#endif /* __aarch64__ */

/* Define (sn)printf formatters for these lwIP types */
#define X8_F  "02x"
#define U16_F "hu"
#define S16_F "hd"
#define X16_F "hx"
#define U32_F "u"
#define S32_F "ld"
#define X32_F "x"

/* If only we could use C99 and get %zu */
#if defined(__aarch64__)
#define SZT_F "lu"
#elif defined(__x86_64__)
#define SZT_F "lu"
#else
#define SZT_F "zu"
#endif

/* Compiler hints for packing structures */
#define PACK_STRUCT_FIELD(x) x
#define PACK_STRUCT_STRUCT __attribute__((packed))
#define PACK_STRUCT_BEGIN
#define PACK_STRUCT_END

/* prototypes for printf() and abort() */
#include <stdio.h>
#include <stdlib.h>

/* Plaform specific diagnostic output */
#define LWIP_PLATFORM_DIAG(message)	do {printf message;} while(0)

#ifdef LWIP_UNIX_EMPTY_ASSERT
#define LWIP_PLATFORM_ASSERT(message)
#else
#define LWIP_PLATFORM_ASSERT(message) do {printf("Assertion \"%s\" failed at line %d in %s\n", \
message, __LINE__, __FILE__); fflush(NULL); abort();} while(0)
#endif

#define LWIP_RAND() ((u32_t)rand())

#endif /* LWIP_ARCH_CC_H */
