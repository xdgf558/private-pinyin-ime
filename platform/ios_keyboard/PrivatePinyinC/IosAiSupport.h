#ifndef PRIVATE_PINYIN_IOS_AI_SUPPORT_H
#define PRIVATE_PINYIN_IOS_AI_SUPPORT_H

#include <stdint.h>

#include <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_SIMULATOR
#include <os/proc.h>

static inline uint64_t private_pinyin_ios_available_memory_bytes(void) {
  return (uint64_t)os_proc_available_memory();
}
#else
static inline uint64_t private_pinyin_ios_available_memory_bytes(void) {
  return 0;
}
#endif

#endif
