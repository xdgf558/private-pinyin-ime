#pragma once

#include <atomic>
#include <optional>

#include <msctf.h>
#include <windows.h>

#include "candidate_window.h"
#include "core_bridge.h"

namespace private_pinyin {

struct KeyMessage;

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfCompositionSink {
 public:
  TextService();

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  HRESULT STDMETHODCALLTYPE Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override;
  HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr* thread_mgr, TfClientId client_id,
                                       DWORD flags) override;
  HRESULT STDMETHODCALLTYPE Deactivate() override;

  HRESULT STDMETHODCALLTYPE OnSetFocus(BOOL foreground) override;
  HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext* context, WPARAM key, LPARAM flags,
                                          BOOL* eaten) override;
  HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext* context, WPARAM key, LPARAM flags,
                                      BOOL* eaten) override;
  HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext* context, WPARAM key, LPARAM flags,
                                        BOOL* eaten) override;
  HRESULT STDMETHODCALLTYPE OnKeyUp(ITfContext* context, WPARAM key, LPARAM flags,
                                    BOOL* eaten) override;
  HRESULT STDMETHODCALLTYPE OnPreservedKey(ITfContext* context, REFGUID guid,
                                           BOOL* eaten) override;

  HRESULT STDMETHODCALLTYPE OnCompositionTerminated(TfEditCookie cookie,
                                                    ITfComposition* composition) override;

  HRESULT apply_output_in_edit_session(TfEditCookie cookie, ITfContext* context,
                                       const OutputSnapshot& output);

 private:
  ~TextService();

  HRESULT advise_key_sink();
  void unadvise_key_sink();
  HRESULT request_edit_session(ITfContext* context, const OutputSnapshot& output);
  HRESULT update_composition(TfEditCookie cookie, ITfContext* context,
                             const std::wstring& preedit);
  HRESULT commit_text(TfEditCookie cookie, ITfContext* context, const std::wstring& text);
  HRESULT clear_composition(TfEditCookie cookie);
  void release_composition();
  std::optional<RECT> candidate_anchor_rect(TfEditCookie cookie, ITfContext* context) const;
  void update_candidate_window(TfEditCookie cookie, ITfContext* context,
                               const OutputSnapshot& output);
  bool should_handle_key(const KeyMessage& message) const;
  void update_input_state(const OutputSnapshot& output);

  std::atomic<ULONG> ref_count_{1};
  ITfThreadMgr* thread_mgr_ = nullptr;
  TfClientId client_id_ = TF_CLIENTID_NULL;
  ITfComposition* composition_ = nullptr;
  CoreBridge core_;
  CandidateWindow candidate_window_;
  bool has_active_input_ = false;
};

}  // namespace private_pinyin
