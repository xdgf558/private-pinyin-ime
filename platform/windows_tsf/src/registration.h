#pragma once

#include <windows.h>

namespace private_pinyin {

HRESULT register_server(HINSTANCE module);
HRESULT unregister_server();

}  // namespace private_pinyin
