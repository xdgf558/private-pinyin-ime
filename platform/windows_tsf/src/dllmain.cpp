#include <windows.h>

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
  }
  return TRUE;
}

extern "C" __declspec(dllexport) HRESULT STDMETHODCALLTYPE DllCanUnloadNow() {
  return private_pinyin::g_object_count.load() == 0 &&
                 private_pinyin::g_lock_count.load() == 0
             ? S_OK
             : S_FALSE;
}

extern "C" __declspec(dllexport) HRESULT STDMETHODCALLTYPE DllGetClassObject(REFCLSID clsid,
                                                                              REFIID iid,
                                                                              void** object) {
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

extern "C" __declspec(dllexport) HRESULT STDMETHODCALLTYPE DllRegisterServer() {
  return private_pinyin::register_server(private_pinyin::g_module);
}

extern "C" __declspec(dllexport) HRESULT STDMETHODCALLTYPE DllUnregisterServer() {
  return private_pinyin::unregister_server();
}
