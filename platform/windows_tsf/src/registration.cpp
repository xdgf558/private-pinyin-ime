#include "registration.h"

#include <msctf.h>

#include <iterator>
#include <string>

#include "com_ptr.h"
#include "guids.h"

namespace private_pinyin {

namespace {

std::wstring guid_to_string(REFGUID guid) {
  wchar_t buffer[64]{};
  StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer)));
  return buffer;
}

HRESULT set_string_value(HKEY key, const wchar_t* name, const std::wstring& value) {
  const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG result = RegSetValueExW(key, name, 0, REG_SZ,
                                     reinterpret_cast<const BYTE*>(value.c_str()), bytes);
  return HRESULT_FROM_WIN32(result);
}

HRESULT write_com_registration(HINSTANCE module) {
  wchar_t module_path[MAX_PATH]{};
  if (GetModuleFileNameW(module, module_path, static_cast<DWORD>(std::size(module_path))) == 0) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  const std::wstring clsid = guid_to_string(kTextServiceClsid);
  const std::wstring clsid_key = L"Software\\Classes\\CLSID\\" + clsid;
  const std::wstring inproc_key = clsid_key + L"\\InprocServer32";

  HKEY key = nullptr;
  LONG result = RegCreateKeyExW(HKEY_CURRENT_USER, clsid_key.c_str(), 0, nullptr, 0, KEY_WRITE,
                                nullptr, &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(result);
  }
  HRESULT hr = set_string_value(key, nullptr, kTextServiceDescription);
  RegCloseKey(key);
  if (FAILED(hr)) {
    return hr;
  }

  result = RegCreateKeyExW(HKEY_CURRENT_USER, inproc_key.c_str(), 0, nullptr, 0, KEY_WRITE,
                           nullptr, &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(result);
  }
  hr = set_string_value(key, nullptr, module_path);
  if (SUCCEEDED(hr)) {
    hr = set_string_value(key, L"ThreadingModel", kThreadingModel);
  }
  RegCloseKey(key);
  return hr;
}

void delete_com_registration() {
  const std::wstring clsid = guid_to_string(kTextServiceClsid);
  const std::wstring clsid_key = L"Software\\Classes\\CLSID\\" + clsid;
  RegDeleteTreeW(HKEY_CURRENT_USER, clsid_key.c_str());
}

std::wstring profile_icon_path(HINSTANCE module) {
  wchar_t module_path[MAX_PATH]{};
  const DWORD length =
      GetModuleFileNameW(module, module_path, static_cast<DWORD>(std::size(module_path)));
  if (length == 0 || length >= std::size(module_path)) {
    return {};
  }

  std::wstring icon_path(module_path, length);
  const std::wstring::size_type separator = icon_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  icon_path.resize(separator + 1);
  icon_path += L"PrivatePinyinInstaller.ico";
  return GetFileAttributesW(icon_path.c_str()) != INVALID_FILE_ATTRIBUTES ? icon_path
                                                                          : std::wstring{};
}

HRESULT register_tsf_profile(HINSTANCE module) {
  ComPtr<ITfInputProcessorProfiles> profiles;
  HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(profiles.put()));
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<ITfCategoryMgr> category_mgr;
  hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(category_mgr.put()));
  if (FAILED(hr)) {
    return hr;
  }

  // Registration must be idempotent because unsigned internal builds are often
  // reinstalled over older packages while the same TIP GUID is already present.
  category_mgr->UnregisterCategory(kTextServiceClsid, GUID_TFCAT_TIP_KEYBOARD,
                                   kTextServiceClsid);
  profiles->RemoveLanguageProfile(kTextServiceClsid, kTextServiceLangId,
                                  kLegacyTextServiceProfileGuid);
  profiles->RemoveLanguageProfile(kTextServiceClsid, kTextServiceLangId,
                                  kTextServiceProfileGuid);
  profiles->Unregister(kTextServiceClsid);

  hr = profiles->Register(kTextServiceClsid);
  if (FAILED(hr)) {
    return hr;
  }

  const std::wstring icon_path = profile_icon_path(module);
  const wchar_t* icon_file = icon_path.empty() ? nullptr : icon_path.c_str();
  const ULONG icon_path_length = static_cast<ULONG>(icon_path.size());
  hr = profiles->AddLanguageProfile(
      kTextServiceClsid, kTextServiceLangId, kTextServiceProfileGuid, kTextServiceDescription,
      static_cast<ULONG>(std::size(kTextServiceDescription) - 1), icon_file, icon_path_length, 0);
  if (FAILED(hr)) {
    return hr;
  }

  return category_mgr->RegisterCategory(kTextServiceClsid, GUID_TFCAT_TIP_KEYBOARD,
                                        kTextServiceClsid);
}

void unregister_tsf_profile() {
  ComPtr<ITfCategoryMgr> category_mgr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(category_mgr.put())))) {
    category_mgr->UnregisterCategory(kTextServiceClsid, GUID_TFCAT_TIP_KEYBOARD,
                                     kTextServiceClsid);
  }

  ComPtr<ITfInputProcessorProfiles> profiles;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(profiles.put())))) {
    profiles->RemoveLanguageProfile(kTextServiceClsid, kTextServiceLangId,
                                    kLegacyTextServiceProfileGuid);
    profiles->RemoveLanguageProfile(kTextServiceClsid, kTextServiceLangId,
                                    kTextServiceProfileGuid);
    profiles->Unregister(kTextServiceClsid);
  }
}

}  // namespace

HRESULT register_server(HINSTANCE module) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool did_initialize = SUCCEEDED(hr);
  if (hr == RPC_E_CHANGED_MODE) {
    hr = S_OK;
  }
  if (FAILED(hr)) {
    return hr;
  }

  hr = write_com_registration(module);
  if (SUCCEEDED(hr)) {
    hr = register_tsf_profile(module);
  }

  if (did_initialize) {
    CoUninitialize();
  }
  return hr;
}

HRESULT unregister_server() {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool did_initialize = SUCCEEDED(hr);
  if (hr == RPC_E_CHANGED_MODE) {
    hr = S_OK;
  }
  if (FAILED(hr)) {
    return hr;
  }

  unregister_tsf_profile();
  delete_com_registration();

  if (did_initialize) {
    CoUninitialize();
  }
  return S_OK;
}

}  // namespace private_pinyin
