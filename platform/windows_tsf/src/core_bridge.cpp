#include "core_bridge.h"

#include <windows.h>

#include <algorithm>
#include <optional>
#include <string>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace private_pinyin {
namespace {

bool file_exists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ensure_directory(const std::wstring& path) {
  if (CreateDirectoryW(path.c_str(), nullptr) != FALSE) {
    return true;
  }
  return GetLastError() == ERROR_ALREADY_EXISTS;
}

std::string wide_to_utf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }

  const int length = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (length <= 1) {
    return {};
  }

  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), length, nullptr, nullptr);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

std::string json_escape(std::string value) {
  std::string escaped;
  escaped.reserve(value.size());
  for (char ch : value) {
    if (ch == '"' || ch == '\\') {
      escaped.push_back('\\');
    }
    escaped.push_back(ch);
  }
  return escaped;
}

std::wstring module_directory() {
  wchar_t module_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(
      reinterpret_cast<HMODULE>(&__ImageBase),
      module_path,
      static_cast<DWORD>(MAX_PATH));
  if (length == 0 || length >= MAX_PATH) {
    return {};
  }

  std::wstring path(module_path, module_path + length);
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  return path.substr(0, separator);
}

std::optional<std::string> read_utf8_file(const std::wstring& path) {
  const HANDLE file = CreateFileW(
      path.c_str(),
      GENERIC_READ,
      FILE_SHARE_READ,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return std::nullopt;
  }

  LARGE_INTEGER size = {};
  if (GetFileSizeEx(file, &size) == FALSE || size.QuadPart < 0 || size.QuadPart > 1024 * 1024) {
    CloseHandle(file);
    return std::nullopt;
  }

  std::string contents(static_cast<size_t>(size.QuadPart), '\0');
  DWORD read = 0;
  const BOOL ok = ReadFile(
      file,
      contents.data(),
      static_cast<DWORD>(contents.size()),
      &read,
      nullptr);
  CloseHandle(file);

  if (ok == FALSE || read != static_cast<DWORD>(contents.size())) {
    return std::nullopt;
  }
  return contents;
}

bool replace_first(std::string& value, const std::string& needle, const std::string& replacement) {
  const size_t position = value.find(needle);
  if (position == std::string::npos) {
    return false;
  }
  value.replace(position, needle.size(), replacement);
  return true;
}

std::string default_settings_template() {
  return "{\n"
         "  \"default_mode\": \"Chinese\",\n"
         "  \"toggle_key\": \"Shift\",\n"
         "  \"candidate_page_size\": 5,\n"
         "  \"enable_prediction\": true,\n"
         "  \"enable_user_learning\": true,\n"
         "  \"strict_privacy_mode\": false,\n"
         "  \"user_lexicon_path\": null,\n"
         "  \"imported_lexicon_path\": null,\n"
         "  \"fuzzy_pinyin\": {\n"
         "    \"zh_z\": false,\n"
         "    \"ch_c\": false,\n"
         "    \"sh_s\": false,\n"
         "    \"n_l\": false,\n"
         "    \"an_ang\": false,\n"
         "    \"en_eng\": false,\n"
         "    \"in_ing\": false\n"
         "  },\n"
         "  \"theme\": \"system\",\n"
         "  \"candidate_font_size\": 14\n"
         "}\n";
}

bool write_utf8_file(const std::wstring& path, const std::string& contents) {
  const HANDLE file = CreateFileW(
      path.c_str(),
      GENERIC_WRITE,
      0,
      nullptr,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }

  DWORD written = 0;
  const BOOL ok = WriteFile(
      file,
      contents.data(),
      static_cast<DWORD>(contents.size()),
      &written,
      nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
  return ok != FALSE && written == contents.size();
}

std::string ensure_settings_file() {
  wchar_t local_app_data_buffer[MAX_PATH] = {};
  const DWORD local_app_data_length = GetEnvironmentVariableW(
      L"LOCALAPPDATA",
      local_app_data_buffer,
      static_cast<DWORD>(MAX_PATH));
  if (local_app_data_length == 0 || local_app_data_length >= MAX_PATH) {
    return {};
  }

  const std::wstring support_dir =
      std::wstring(local_app_data_buffer) + L"\\PrivatePinyin";
  if (!ensure_directory(support_dir)) {
    return {};
  }

  const std::wstring settings_path = support_dir + L"\\settings.json";
  const std::wstring user_lexicon_path = support_dir + L"\\user_lexicon.sqlite";
  const std::wstring imported_lexicon_path = support_dir + L"\\imported_lexicon.tsv";
  if (!file_exists(settings_path)) {
    std::string user_lexicon_utf8 = wide_to_utf8(user_lexicon_path);
    std::replace(user_lexicon_utf8.begin(), user_lexicon_utf8.end(), '\\', '/');
    std::string imported_lexicon_utf8 = wide_to_utf8(imported_lexicon_path);
    std::replace(imported_lexicon_utf8.begin(), imported_lexicon_utf8.end(), '\\', '/');

    std::string contents;
    const std::wstring template_path = module_directory() + L"\\default_settings.json";
    if (auto packaged_template = read_utf8_file(template_path)) {
      contents = *packaged_template;
    } else {
      contents = default_settings_template();
    }

    const std::string replacement =
        "\"user_lexicon_path\": \"" + json_escape(user_lexicon_utf8) + "\"";
    if (!replace_first(contents, "\"user_lexicon_path\": null", replacement)) {
      return {};
    }
    const std::string imported_replacement =
        "\"imported_lexicon_path\": \"" + json_escape(imported_lexicon_utf8) + "\"";
    if (!replace_first(contents, "\"imported_lexicon_path\": null", imported_replacement)) {
      return {};
    }

    if (!write_utf8_file(settings_path, contents)) {
      return {};
    }
  }

  return wide_to_utf8(settings_path);
}

}  // namespace

CoreBridge::~CoreBridge() {
  reset();
}

bool CoreBridge::initialize() {
  reset();
  settings_path_ = ensure_settings_file();
  engine_ = settings_path_.empty() ? ime_engine_new(nullptr) : ime_engine_new(settings_path_.c_str());
  if (engine_ == nullptr) {
    return false;
  }

  MEMORYSTATUSEX memory_status{};
  memory_status.dwLength = sizeof(memory_status);
  if (GlobalMemoryStatusEx(&memory_status) != FALSE) {
    const uint64_t physical_memory_mb = memory_status.ullTotalPhys / (1024ULL * 1024ULL);
    (void)ime_engine_enable_desktop_ai(
        engine_, IME_AI_PLATFORM_WINDOWS, physical_memory_mb, 0);
  }

  session_ = ime_session_new(engine_);
  if (session_ == nullptr) {
    reset();
    return false;
  }

  return true;
}

void CoreBridge::reset() {
  if (session_ != nullptr) {
    ime_session_free(session_);
    session_ = nullptr;
  }
  if (engine_ != nullptr) {
    ime_engine_free(engine_);
    engine_ = nullptr;
  }
  settings_path_.clear();
}

void CoreBridge::reset_session() {
  if (session_ == nullptr) {
    return;
  }
  (void)take_output(ime_session_reset(session_));
}

void CoreBridge::set_secure_input(bool secure_input) {
  if (session_ == nullptr) {
    return;
  }
  (void)ime_session_set_secure_input(session_, secure_input ? 1 : 0);
}

bool CoreBridge::clear_user_lexicon() {
  if (engine_ == nullptr) {
    return false;
  }
  return ime_engine_clear_user_lexicon(engine_) != 0;
}

bool CoreBridge::export_user_lexicon(const std::wstring& export_path) {
  if (engine_ == nullptr || export_path.empty()) {
    return false;
  }
  const std::string export_path_utf8 = wide_to_utf8(export_path);
  return !export_path_utf8.empty() &&
         ime_engine_export_user_lexicon(engine_, export_path_utf8.c_str()) != 0;
}

std::optional<OutputSnapshot> CoreBridge::feed_key(const ImeKeyEvent& event) {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_feed_key(session_, event));
}

std::optional<OutputSnapshot> CoreBridge::commit_candidate(int index) {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_commit_candidate(session_, index));
}

std::optional<OutputSnapshot> CoreBridge::toggle_mode() {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_toggle_mode(session_));
}

std::optional<OutputSnapshot> CoreBridge::take_output(ImeOutput* output) {
  if (output == nullptr) {
    return std::nullopt;
  }

  OutputSnapshot snapshot;
  snapshot.preedit = utf8_to_wide(output->preedit);
  snapshot.commit_text = utf8_to_wide(output->commit_text);
  snapshot.should_update_preedit = output->should_update_preedit != 0;
  snapshot.should_commit = output->should_commit != 0;
  snapshot.should_show_candidates = output->should_show_candidates != 0;

  if (output->candidate_count > 0 && output->candidates != nullptr) {
    snapshot.candidates.reserve(static_cast<size_t>(output->candidate_count));
    for (int i = 0; i < output->candidate_count; ++i) {
      const ImeCandidate& candidate = output->candidates[i];
      snapshot.candidates.push_back({
          utf8_to_wide(candidate.text),
          utf8_to_wide(candidate.pinyin),
          candidate.score,
          utf8_to_wide(candidate.source),
      });
    }
  }

  ime_output_free(output);
  return snapshot;
}

std::wstring utf8_to_wide(const char* value) {
  if (value == nullptr || value[0] == '\0') {
    return {};
  }

  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, nullptr, 0);
  if (length <= 1) {
    return {};
  }

  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result.data(), length);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

}  // namespace private_pinyin
