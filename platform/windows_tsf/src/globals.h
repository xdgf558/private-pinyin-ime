#pragma once

#include <atomic>

#include <windows.h>

namespace private_pinyin {

extern HINSTANCE g_module;
extern std::atomic<long> g_object_count;
extern std::atomic<long> g_lock_count;

}  // namespace private_pinyin
