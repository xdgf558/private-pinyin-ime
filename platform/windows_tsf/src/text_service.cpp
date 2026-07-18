#include "text_service.h"

#include <iterator>
#include <new>
#include <optional>
#include <string>
#include <utility>

#include <oleauto.h>
#include <initguid.h>
#include <inputscope.h>
#include <shellapi.h>

#include "com_ptr.h"
#include "globals.h"
#include "guids.h"
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

HRESULT set_caret_after_range(TfEditCookie cookie, ITfContext* context, ITfRange* range) {
  if (context == nullptr || range == nullptr) {
    return E_POINTER;
  }

  ComPtr<ITfRange> caret;
  HRESULT hr = range->Clone(caret.put());
  if (FAILED(hr)) {
    return hr;
  }

  hr = caret->Collapse(cookie, TF_ANCHOR_END);
  if (FAILED(hr)) {
    return hr;
  }

  TF_SELECTION selection{};
  selection.range = caret.get();
  selection.style.ase = TF_AE_NONE;
  selection.style.fInterimChar = FALSE;
  return context->SetSelection(cookie, 1, &selection);
}

HRESULT launch_preferences(HWND parent) {
  wchar_t module_path[MAX_PATH]{};
  const DWORD module_path_length =
      GetModuleFileNameW(g_module, module_path, static_cast<DWORD>(std::size(module_path)));
  if (module_path_length == 0 || module_path_length == std::size(module_path)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  std::wstring settings_path(module_path, module_path_length);
  const std::wstring::size_type separator = settings_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return E_FAIL;
  }
  settings_path.resize(separator + 1);
  settings_path += L"open-settings.ps1";
  if (GetFileAttributesW(settings_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  wchar_t windows_directory[MAX_PATH]{};
  const UINT windows_directory_length =
      GetWindowsDirectoryW(windows_directory, static_cast<UINT>(std::size(windows_directory)));
  if (windows_directory_length == 0 || windows_directory_length >= std::size(windows_directory)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  std::wstring powershell_path(windows_directory, windows_directory_length);
  powershell_path += L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
  const std::wstring arguments =
      L"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass "
      L"-WindowStyle Hidden -STA -File \"" +
      settings_path + L"\"";

  SHELLEXECUTEINFOW execute_info{};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  execute_info.hwnd = parent;
  execute_info.lpVerb = L"open";
  execute_info.lpFile = powershell_path.c_str();
  execute_info.lpParameters = arguments.c_str();
  execute_info.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&execute_info)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  if (execute_info.hProcess != nullptr) {
    WaitForSingleObject(execute_info.hProcess, INFINITE);
    CloseHandle(execute_info.hProcess);
  }
  return S_OK;
}

class SecureInputEditSession final : public ITfEditSession {
 public:
  explicit SecureInputEditSession(ITfContext* context) : context_(context) {
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
    TF_SELECTION selection{};
    ULONG fetched = 0;
    HRESULT hr = context_->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched == 0 || selection.range == nullptr) {
      return SUCCEEDED(hr) ? S_FALSE : hr;
    }

    ComPtr<ITfProperty> property;
    hr = context_->GetProperty(GUID_PROP_INPUTSCOPE, property.put());
    if (SUCCEEDED(hr)) {
      VARIANT value;
      VariantInit(&value);
      hr = property->GetValue(cookie, selection.range, &value);
      if (SUCCEEDED(hr)) {
        secure_input_ = variant_contains_password_scope(value);
      }
      VariantClear(&value);
    }
    selection.range->Release();
    return SUCCEEDED(hr) ? S_OK : hr;
  }

  bool secure_input() const {
    return secure_input_;
  }

 private:
  ~SecureInputEditSession() {
    context_->Release();
  }

  static bool variant_contains_password_scope(const VARIANT& value) {
    if (value.vt == VT_I4) {
      return value.lVal == IS_PASSWORD;
    }
    if (value.vt != VT_UNKNOWN || value.punkVal == nullptr) {
      return false;
    }

    ComPtr<ITfInputScope> input_scope;
    if (FAILED(value.punkVal->QueryInterface(IID_ITfInputScope,
                                             reinterpret_cast<void**>(input_scope.put())))) {
      return false;
    }
    InputScope* scopes = nullptr;
    UINT count = 0;
    if (FAILED(input_scope->GetInputScopes(&scopes, &count))) {
      return false;
    }
    bool is_password = false;
    for (UINT index = 0; index < count; ++index) {
      if (scopes[index] == IS_PASSWORD) {
        is_password = true;
        break;
      }
    }
    CoTaskMemFree(scopes);
    return is_password;
  }

  std::atomic<ULONG> ref_count_{1};
  ITfContext* context_;
  // Fail closed until the TSF input scope has been read successfully.
  bool secure_input_ = true;
};

bool context_uses_secure_input(TfClientId client_id, ITfContext* context) {
  if (client_id == TF_CLIENTID_NULL || context == nullptr) {
    return true;
  }
  auto* edit_session = new (std::nothrow) SecureInputEditSession(context);
  if (edit_session == nullptr) {
    return true;
  }
  HRESULT edit_result = E_FAIL;
  const HRESULT request_result = context->RequestEditSession(
      client_id, edit_session, TF_ES_SYNC | TF_ES_READ, &edit_result);
  const bool secure_input = FAILED(request_result) || FAILED(edit_result) ||
                            edit_session->secure_input();
  edit_session->Release();
  return secure_input;
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
  } else if (iid == IID_ITfFunctionProvider) {
    *object = static_cast<ITfFunctionProvider*>(this);
  } else if (iid == IID_ITfFunction || iid == IID_ITfFnConfigure) {
    *object = static_cast<ITfFnConfigure*>(this);
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
    return hr;
  }
  advise_function_provider();
  return hr;
}

HRESULT TextService::Deactivate() {
  unadvise_function_provider();
  unadvise_key_sink();
  candidate_window_.hide();
  release_composition();
  has_active_input_ = false;
  shift_pressed_ = false;
  shift_used_as_modifier_ = false;
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
    shift_pressed_ = false;
    shift_used_as_modifier_ = false;
    core_.reset_session();
    core_.set_secure_input(false);
  }
  return S_OK;
}

HRESULT TextService::OnTestKeyDown(ITfContext* /*context*/, WPARAM key, LPARAM flags,
                                   BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  if (key == VK_SHIFT) {
    *eaten = TRUE;
    return S_OK;
  }
  if (shift_pressed_) {
    shift_used_as_modifier_ = true;
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

  if (key == VK_SHIFT) {
    shift_pressed_ = true;
    shift_used_as_modifier_ = false;
    *eaten = TRUE;
    return S_OK;
  }
  if (shift_pressed_) {
    shift_used_as_modifier_ = true;
  }

  KeyMessage message = map_windows_key(key, flags);
  if (!should_handle_key(message)) {
    return S_OK;
  }

  ImeKeyEvent event = to_ime_key_event(message);
  core_.set_secure_input(context_uses_secure_input(client_id_, context));
  std::optional<OutputSnapshot> output = core_.feed_key(event);
  if (!output.has_value()) {
    return S_OK;
  }

  apply_core_output(context, *output);
  update_input_state(*output);

  *eaten = TRUE;
  return S_OK;
}

HRESULT TextService::OnTestKeyUp(ITfContext* /*context*/, WPARAM key, LPARAM /*flags*/,
                                 BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  if (key != VK_SHIFT) {
    *eaten = FALSE;
    return S_OK;
  }

  const bool should_toggle = shift_pressed_ && !shift_used_as_modifier_;
  *eaten = should_toggle ? TRUE : FALSE;
  if (!should_toggle) {
    shift_pressed_ = false;
    shift_used_as_modifier_ = false;
  }
  return S_OK;
}

HRESULT TextService::OnKeyUp(ITfContext* context, WPARAM key, LPARAM flags,
                             BOOL* eaten) {
  if (eaten == nullptr) {
    return E_POINTER;
  }
  *eaten = FALSE;
  if (key != VK_SHIFT) {
    return S_OK;
  }

  const bool should_toggle = shift_pressed_ && !shift_used_as_modifier_;
  shift_pressed_ = false;
  shift_used_as_modifier_ = false;
  if (!should_toggle) {
    return S_OK;
  }

  const KeyMessage message = map_windows_key(key, flags);
  core_.set_secure_input(context_uses_secure_input(client_id_, context));
  std::optional<OutputSnapshot> output = core_.feed_key(to_ime_key_event(message));
  if (output.has_value()) {
    apply_core_output(context, *output);
    update_input_state(*output);
  }
  *eaten = TRUE;
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

HRESULT TextService::GetType(GUID* guid) {
  if (guid == nullptr) {
    return E_POINTER;
  }
  *guid = kTextServiceClsid;
  return S_OK;
}

HRESULT TextService::GetDescription(BSTR* description) {
  if (description == nullptr) {
    return E_POINTER;
  }
  *description = SysAllocString(kTextServiceDescription);
  return *description != nullptr ? S_OK : E_OUTOFMEMORY;
}

HRESULT TextService::GetFunction(REFGUID guid, REFIID iid, IUnknown** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  *object = nullptr;
  if (guid != GUID_NULL || iid != IID_ITfFnConfigure) {
    return E_NOINTERFACE;
  }
  return QueryInterface(iid, reinterpret_cast<void**>(object));
}

HRESULT TextService::GetDisplayName(BSTR* name) {
  if (name == nullptr) {
    return E_POINTER;
  }
  *name = SysAllocString(L"偏好设置");
  return *name != nullptr ? S_OK : E_OUTOFMEMORY;
}

HRESULT TextService::Show(HWND parent, LANGID /*language_id*/, REFGUID /*profile_guid*/) {
  return launch_preferences(parent);
}

HRESULT TextService::apply_output_in_edit_session(TfEditCookie cookie, ITfContext* context,
                                                  const OutputSnapshot& output) {
  HRESULT hr = S_OK;

  if (output.should_commit && !output.commit_text.empty()) {
    hr = commit_text(cookie, context, output.commit_text);
  }

  if (SUCCEEDED(hr) && output.should_update_preedit) {
    if (output.preedit.empty()) {
      hr = clear_composition(cookie, context);
    } else {
      hr = update_composition(cookie, context, output.preedit);
    }
  }

  if (SUCCEEDED(hr)) {
    update_candidate_window(cookie, context, output);
  }

  return hr;
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

HRESULT TextService::advise_function_provider() {
  if (thread_mgr_ == nullptr || client_id_ == TF_CLIENTID_NULL) {
    return E_UNEXPECTED;
  }

  ComPtr<ITfSourceSingle> source;
  HRESULT hr = thread_mgr_->QueryInterface(IID_PPV_ARGS(source.put()));
  if (FAILED(hr)) {
    return hr;
  }

  hr = source->AdviseSingleSink(client_id_, IID_ITfFunctionProvider,
                                static_cast<ITfFunctionProvider*>(this));
  if (SUCCEEDED(hr)) {
    function_provider_advised_ = true;
  }
  return hr;
}

void TextService::unadvise_function_provider() {
  if (!function_provider_advised_ || thread_mgr_ == nullptr ||
      client_id_ == TF_CLIENTID_NULL) {
    return;
  }

  ComPtr<ITfSourceSingle> source;
  if (SUCCEEDED(thread_mgr_->QueryInterface(IID_PPV_ARGS(source.put())))) {
    source->UnadviseSingleSink(client_id_, IID_ITfFunctionProvider);
  }
  function_provider_advised_ = false;
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

void TextService::apply_core_output(ITfContext* context, const OutputSnapshot& output) {
  if (context != nullptr) {
    const HRESULT edit_result = request_edit_session(context, output);
    if (SUCCEEDED(edit_result)) {
      return;
    }
  }

  if (output.should_show_candidates) {
    candidate_window_.show(output.candidates);
  } else {
    candidate_window_.hide();
  }
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

  hr = range->SetText(cookie, 0, preedit.c_str(), static_cast<LONG>(preedit.size()));
  if (FAILED(hr)) {
    return hr;
  }
  return set_caret_after_range(cookie, context, range.get());
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
    if (SUCCEEDED(hr)) {
      hr = set_caret_after_range(cookie, context, range.get());
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
  if (SUCCEEDED(hr)) {
    hr = set_caret_after_range(cookie, context, selection.range);
  }
  selection.range->Release();
  return hr;
}

HRESULT TextService::clear_composition(TfEditCookie cookie, ITfContext* context) {
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
  if (SUCCEEDED(hr)) {
    hr = set_caret_after_range(cookie, context, range.get());
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

std::optional<RECT> TextService::candidate_anchor_rect(TfEditCookie cookie,
                                                       ITfContext* context) const {
  if (context == nullptr) {
    return std::nullopt;
  }

  ComPtr<ITfContextView> context_view;
  HRESULT hr = context->GetActiveView(context_view.put());
  if (FAILED(hr)) {
    return std::nullopt;
  }

  ComPtr<ITfRange> range;
  if (composition_ != nullptr) {
    hr = composition_->GetRange(range.put());
    if (FAILED(hr)) {
      return std::nullopt;
    }
  } else {
    TF_SELECTION selection{};
    ULONG fetched = 0;
    hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched == 0 || selection.range == nullptr) {
      return std::nullopt;
    }
    range.reset(selection.range);
  }

  RECT rect{};
  BOOL clipped = FALSE;
  hr = context_view->GetTextExt(cookie, range.get(), &rect, &clipped);
  if (FAILED(hr)) {
    return std::nullopt;
  }
  return rect;
}

void TextService::update_candidate_window(TfEditCookie cookie, ITfContext* context,
                                          const OutputSnapshot& output) {
  if (!output.should_show_candidates || output.candidates.empty()) {
    candidate_window_.hide();
    return;
  }

  std::optional<RECT> anchor = candidate_anchor_rect(cookie, context);
  candidate_window_.show(output.candidates, anchor.has_value() ? &anchor.value() : nullptr);
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
