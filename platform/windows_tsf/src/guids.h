#pragma once

#include <windows.h>

namespace private_pinyin {

inline constexpr CLSID kTextServiceClsid = {
    0x6a7d5301,
    0x42d7,
    0x41fb,
    {0x99, 0x54, 0x4f, 0x98, 0xa6, 0x3f, 0x62, 0x10}};

inline constexpr GUID kTextServiceProfileGuid = {
    0xb6332fc3,
    0x833d,
    0x4f7e,
    {0xa1, 0x12, 0x58, 0x95, 0x85, 0x1c, 0xda, 0x34}};

inline constexpr GUID kDisplayAttributeGuid = {
    0x1ab6a5c4,
    0xb625,
    0x4b69,
    {0x85, 0x30, 0x44, 0x99, 0x35, 0x3f, 0x6b, 0x52}};

inline constexpr LANGID kTextServiceLangId =
    MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);

inline constexpr wchar_t kTextServiceDescription[] = L"PrivatePinyin IME";
inline constexpr wchar_t kThreadingModel[] = L"Apartment";

}  // namespace private_pinyin
