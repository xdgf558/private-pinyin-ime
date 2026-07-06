#include "class_factory.h"

#include <new>

#include "globals.h"
#include "text_service.h"

namespace private_pinyin {

ClassFactory::ClassFactory() {
  ++g_object_count;
}

ClassFactory::~ClassFactory() {
  --g_object_count;
}

HRESULT ClassFactory::QueryInterface(REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (iid == IID_IUnknown || iid == IID_IClassFactory) {
    *object = static_cast<IClassFactory*>(this);
    AddRef();
    return S_OK;
  }

  return E_NOINTERFACE;
}

ULONG ClassFactory::AddRef() {
  return ++ref_count_;
}

ULONG ClassFactory::Release() {
  const ULONG value = --ref_count_;
  if (value == 0) {
    delete this;
  }
  return value;
}

HRESULT ClassFactory::CreateInstance(IUnknown* outer, REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (outer != nullptr) {
    return CLASS_E_NOAGGREGATION;
  }

  auto* service = new (std::nothrow) TextService();
  if (service == nullptr) {
    return E_OUTOFMEMORY;
  }

  const HRESULT result = service->QueryInterface(iid, object);
  service->Release();
  return result;
}

HRESULT ClassFactory::LockServer(BOOL lock) {
  if (lock) {
    ++g_lock_count;
  } else {
    --g_lock_count;
  }
  return S_OK;
}

}  // namespace private_pinyin
