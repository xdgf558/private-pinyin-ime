#include "text_service.h"

#include <new>
#include <utility>

#include "com_ptr.h"
#include "globals.h"
#include "key_map.h"

namespace private_pinyin {

namespace {

bool is_composition_scoped_key(int key_code) {
  switch (key_code) {
    case IME_KEY_ENTER:
    case IME_KEY_BACKSPACE:
    case IME_KEY_ESCAPE:
    case IME_KEY_PAGE_UP:
    case IME_KEY_PAGE_DOWN:
    case IME_KEY_ARROW_UP:
    case IME_KEY_ARROW_DOWN:
    case IME_KEY_DIGIT:
      return true;
    default:
      return false;
  }
}

bool is_shift_passthrough_key(int key_code) {
  switch (key_code) {
    case IME_KEY_CHARACTER:
    case IME_KEY_DIGIT:
    case IME_KEY_COMMA:
    case IME_KEY_PERIOD:
    case IME_KEY_MINUS:
    case IME_KEY_EQUAL:
    case IME_KEY_APOSTROPHE:
    case IME_KEY_SEMICOLON:
      return true;
    default:
      return false;
  }
}

class EditSession final : public ITfEditSession {
 public:
  EditSession(TextService* service, ITfContext* context, OutputSnapshot output)
      : service_(service), context_(context), output_(std::move(output)) {
    service_->AddRef();
    context_->AddRef();
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
      *object = static_cast<ITfEditSession*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return ++ref_count_;
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG value = --ref_count_;
    if (value == 0) {
      delete this;
    }
    return value;
  }

  HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override {
    return service_->apply_output_in_edit_session(cookie, context_, output_);
  }

 private:
  ~EditSession() {
    context_->Release();
    service_->Release();
  }

  std::atomic<ULONG> ref_count_{1};
  TextService* service_;
  ITfContext* context_;
  OutputSnapshot output_;
};

}  // namespace

TextService::TextService() {
  ++g_object_count;
}

TextService::~TextService() {
  Deactivate();
  --g_object_count;
}

HRESULT TextService::QueryInterface(REFIID iid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;

  if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor ||
      iid == IID_ITfTextInputProcessorEx) {
    *object = static_cast<ITfTextInputProcessorEx*>(this);
  } else if (iid == IID_ITfKeyEventSink) {
    *object = static_cast<ITfKeyEventSink*>(this);
  } else if (iid == IID_ITfCompositionSink) {
    *object = static_cast<ITfCompositionSink*>(this);
  } else {
    return E_NOINTERFACE;
  }

  AddRef();
  return S_OK;
}

ULONG TextService::AddRef() {
  return ++ref_count_;
}

ULONG TextService::Release() {
  const ULONG value = --ref_count_;
  if (value == 0) {
    delete this;
  }
  return value;
}

HRESULT TextService::Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) {
  return ActivateEx(thread_mgr, client_id, 0);
}

HRESULT TextService::ActivateEx(ITfThreadMgr* thread_mgr, TfClientId client_id, DWORD /*flags*/) {
  if (thread_mgr == nullptr) {
    return E_INVALIDARG;
  }

  Deactivate();
  thread_mgr_ = thread_mgr;
  thread_mgr_->AddRef();
  client_id_ = client_id;

  if (!core_.initialize()) {
    Deactivate();
    return E_FAIL;
  }

  const HRESULT hr = advise_key_sink();
  if (FAILED(hr)) {
    Deactivate();
  }
  return hr;
}

HRESULT TextService::Deactivate() {
  unadvise_key_sink();
  candidate_window_.hide();
  release_composition();
  has_active_input_ = false;
  core_.reset();

  if (thread_mgr_ != nullptr) {
    thread_mgr_->Release();
    thread_mgr_ = nullptr;
  }
  client_id_ = TF_CLIENTID_NULL;
  return S_OK;
}

HRESULT TextService::OnSetFocus(BOOL foreground) {
  if (!foreground) {
    candidate_window_.hide();
    has_active_input_ = false;
    core_.reset_session();
  }
  return S_OK;
}

HRESULT TextService::OnTestKeyDown(ITfContext* /*context*/, WPARAM key, LPARAM flags,
                                   BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  const KeyMessage message = map_windows_key(key, flags);
  *eaten = should_handle_key(message) ? TRUE : FALSE;
  return S_OK;
}

HRESULT TextService::OnKeyDown(ITfContext* context, WPARAM key, LPARAM flags, BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  *eaten = FALSE;

  KeyMessage message = map_windows_key(key, flags);
  if (!should_handle_key(message)) {
    return S_OK;
  }

  ImeKeyEvent event = to_ime_key_event(message);
  std::optional<OutputSnapshot> output = core_.feed_key(event);
  if (!output.has_value()) {
    return S_OK;
  }

  if (context != nullptr) {
    request_edit_session(context, *output);
  }

  update_input_state(*output);

  if (output->should_show_candidates) {
    candidate_window_.show(output->candidates);
  } else {
    candidate_window_.hide();
  }

  *eaten = TRUE;
  return S_OK;
}

HRESULT TextService::OnTestKeyUp(ITfContext* /*context*/, WPARAM /*key*/, LPARAM /*flags*/,
                                 BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  *eaten = FALSE;
  return S_OK;
}

HRESULT TextService::OnKeyUp(ITfContext* /*context*/, WPARAM /*key*/, LPARAM /*flags*/,
                             BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  *eaten = FALSE;
  return S_OK;
}

HRESULT TextService::OnPreservedKey(ITfContext* /*context*/, REFGUID /*guid*/, BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  *eaten = FALSE;
  return S_OK;
}

HRESULT TextService::OnCompositionTerminated(TfEditCookie /*cookie*/,
                                             ITfComposition* composition) {
  if (composition_ == composition) {
    release_composition();
    candidate_window_.hide();
    has_active_input_ = false;
    core_.reset_session();
  }
  return S_OK;
}

HRESULT TextService::apply_output_in_edit_session(TfEditCookie cookie, ITfContext* context,
                                                  const OutputSnapshot& output) {
  if (output.should_commit && !output.commit_text.empty()) {
    return commit_text(cookie, context, output.commit_text);
  }

  if (output.should_update_preedit) {
    if (output.preedit.empty()) {
      return clear_composition(cookie);
    }
    return update_composition(cookie, context, output.preedit);
  }

  return S_OK;
}

HRESULT TextService::advise_key_sink() {
  if (thread_mgr_ == nullptr) {
    return E_UNEXPECTED;
  }

  ComPtr<ITfKeystrokeMgr> keystroke_mgr;
  HRESULT hr = thread_mgr_->QueryInterface(IID_PPV_ARGS(keystroke_mgr.put()));
  if (FAILED(hr)) {
    return hr;
  }

  return keystroke_mgr->AdviseKeyEventSink(client_id_, static_cast<ITfKeyEventSink*>(this), TRUE);
}

void TextService::unadvise_key_sink() {
  if (thread_mgr_ == nullptr || client_id_ == TF_CLIENTID_NULL) {
    return;
  }

  ComPtr<ITfKeystrokeMgr> keystroke_mgr;
  if (SUCCEEDED(thread_mgr_->QueryInterface(IID_PPV_ARGS(keystroke_mgr.put())))) {
    keystroke_mgr->UnadviseKeyEventSink(client_id_);
  }
}

HRESULT TextService::request_edit_session(ITfContext* context, const OutputSnapshot& output) {
  if (context == nullptr || client_id_ == TF_CLIENTID_NULL) {
    return E_INVALIDARG;
  }

  auto* edit_session = new (std::nothrow) EditSession(this, context, output);
  if (edit_session == nullptr) {
    return E_OUTOFMEMORY;
  }

  HRESULT edit_result = S_OK;
  const HRESULT hr =
      context->RequestEditSession(client_id_, edit_session, TF_ES_SYNC | TF_ES_READWRITE,
                                  &edit_result);
  edit_session->Release();
  return FAILED(hr) ? hr : edit_result;
}

HRESULT TextService::update_composition(TfEditCookie cookie, ITfContext* context,
                                        const std::wstring& preedit) {
  if (composition_ == nullptr) {
    ComPtr<ITfContextComposition> context_composition;
    HRESULT hr = context->QueryInterface(IID_PPV_ARGS(context_composition.put()));
    if (FAILED(hr)) {
      return hr;
    }

    TF_SELECTION selection{};
    ULONG fetched = 0;
    hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched == 0 || selection.range == nullptr) {
      return FAILED(hr) ? hr : E_FAIL;
    }

    hr = context_composition->StartComposition(cookie, selection.range,
                                               static_cast<ITfCompositionSink*>(this),
                                               &composition_);
    selection.range->Release();
    if (FAILED(hr)) {
      return hr;
    }
  }

  ComPtr<ITfRange> range;
  HRESULT hr = composition_->GetRange(range.put());
  if (FAILED(hr)) {
    return hr;
  }

  return range->SetText(cookie, 0, preedit.c_str(), static_cast<LONG>(preedit.size()));
}

HRESULT TextService::commit_text(TfEditCookie cookie, ITfContext* context,
                                 const std::wstring& text) {
  if (composition_ != nullptr) {
    ComPtr<ITfRange> range;
    HRESULT hr = composition_->GetRange(range.put());
    if (FAILED(hr)) {
      return hr;
    }
    hr = range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
    if (SUCCEEDED(hr)) {
      hr = composition_->EndComposition(cookie);
    }
    release_composition();
    return hr;
  }

  TF_SELECTION selection{};
  ULONG fetched = 0;
  HRESULT hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
  if (FAILED(hr) || fetched == 0 || selection.range == nullptr) {
    return FAILED(hr) ? hr : E_FAIL;
  }
  hr = selection.range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
  selection.range->Release();
  return hr;
}

HRESULT TextService::clear_composition(TfEditCookie cookie) {
  if (composition_ == nullptr) {
    return S_OK;
  }

  ComPtr<ITfRange> range;
  HRESULT hr = composition_->GetRange(range.put());
  if (SUCCEEDED(hr)) {
    hr = range->SetText(cookie, 0, L"", 0);
  }
  if (SUCCEEDED(hr)) {
    hr = composition_->EndComposition(cookie);
  }
  release_composition();
  return hr;
}

void TextService::release_composition() {
  if (composition_ != nullptr) {
    composition_->Release();
    composition_ = nullptr;
  }
}

bool TextService::should_handle_key(const KeyMessage& message) const {
  if (!message.handled_by_ime) {
    return false;
  }

  if (message.key_code == IME_KEY_CTRL_SPACE) {
    return true;
  }

  if (message.ctrl || message.alt || message.meta) {
    return false;
  }

  if (message.shift && is_shift_passthrough_key(message.key_code)) {
    return false;
  }

  if (is_composition_scoped_key(message.key_code)) {
    return has_active_input_;
  }

  return true;
}

void TextService::update_input_state(const OutputSnapshot& output) {
  has_active_input_ =
      !output.preedit.empty() || output.should_show_candidates || !output.candidates.empty();
}

}  // namespace private_pinyin
