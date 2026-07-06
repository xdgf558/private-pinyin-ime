#pragma once

#include <atomic>

#include <windows.h>

namespace private_pinyin {

class ClassFactory final : public IClassFactory {
 public:
  ClassFactory();

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** object) override;
  HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override;

 private:
  ~ClassFactory();

  std::atomic<ULONG> ref_count_{1};
};

}  // namespace private_pinyin
