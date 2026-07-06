#include <windows.h>

#include "candidate_window.h"
#include "class_factory.h"
#include "globals.h"
#include "guids.h"
#include "registration.h"

namespace private_pinyin {

HINSTANCE g_module = nullptr;
std::atomic<long> g_object_count = 0;
std::atomic<long> g_lock_count = 0;

}  // namespace private_pinyin

BOOL APIENTRY DllMain(HINSTANCE instance, DWORD reason, LPVOID /*reserved*/) {
  if (reason == DLL_PROCESS_ATTACH) {
    private_pinyin::g_module = instance;
    DisableThreadLibraryCalls(instance);
  } else if (reason == DLL_PROCESS_DETACH) {
    private_pinyin::CandidateWindow::unregister_window_class();
  }
  return TRUE;
}

STDAPI DllCanUnloadNow() {
  return private_pinyin::g_object_count.load() == 0 &&
                 private_pinyin::g_lock_count.load() == 0
             ? S_OK
             : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (clsid != private_pinyin::kTextServiceClsid) {
    return CLASS_E_CLASSNOTAVAILABLE;
  }

  auto* factory = new (std::nothrow) private_pinyin::ClassFactory();
  if (factory == nullptr) {
    return E_OUTOFMEMORY;
  }

  const HRESULT hr = factory->QueryInterface(iid, object);
  factory->Release();
  return hr;
}

STDAPI DllRegisterServer() {
  return private_pinyin::register_server(private_pinyin::g_module);
}

STDAPI DllUnregisterServer() {
  return private_pinyin::unregister_server();
}
