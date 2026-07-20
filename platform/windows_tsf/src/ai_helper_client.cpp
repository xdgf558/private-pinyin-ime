#include "ai_helper_client.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwchar>
#include <iterator>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <windows.h>
#include <bcrypt.h>
#include <sddl.h>

namespace private_pinyin {
namespace {

constexpr std::uint32_t kProtocolMagic = 0x50504139;
constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumPayloadBytes = 64 * 1024;
constexpr ULONGLONG kPipeConnectTimeoutMilliseconds = 5000;
constexpr ULONGLONG kPipeReadTimeoutMilliseconds = 5000;
constexpr std::uint32_t kProbeHelperIdleTimeoutMilliseconds = 15000;
constexpr wchar_t kTokenEnvironmentKey[] = L"PRIVATE_PINYIN_AI_HELPER_TOKEN";

enum class Opcode : std::uint16_t {
  kAuthenticate = 1,
  kHealth = 2,
  kMockInference = 3,
  kCancel = 4,
  kShutdown = 5,
  kAuthenticated = 0x8001,
  kHealthy = 0x8002,
  kMockCompleted = 0x8003,
  kCancelled = 0x8004,
  kAcknowledged = 0x8005,
  kError = 0x80ff,
};

struct Frame {
  Opcode opcode = Opcode::kError;
  std::uint64_t request_id = 0;
  std::vector<std::uint8_t> payload;
};

class ScopedHandle final {
 public:
  ScopedHandle() = default;
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}
  ~ScopedHandle() { reset(); }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  ScopedHandle(ScopedHandle&& other) noexcept
      : handle_(std::exchange(other.handle_, INVALID_HANDLE_VALUE)) {}
  ScopedHandle& operator=(ScopedHandle&& other) noexcept {
    if (this != &other) {
      reset();
      handle_ = std::exchange(other.handle_, INVALID_HANDLE_VALUE);
    }
    return *this;
  }

  HANDLE get() const { return handle_; }
  bool valid() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }
  void reset(HANDLE handle = INVALID_HANDLE_VALUE) {
    if (valid()) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};

struct LocalFreeDeleter {
  void operator()(void* value) const {
    if (value != nullptr) {
      LocalFree(value);
    }
  }
};

using LocalPointer = std::unique_ptr<void, LocalFreeDeleter>;

void append_u16(std::vector<std::uint8_t>* bytes, std::uint16_t value) {
  bytes->push_back(static_cast<std::uint8_t>(value & 0xff));
  bytes->push_back(static_cast<std::uint8_t>((value >> 8) & 0xff));
}

void append_u32(std::vector<std::uint8_t>* bytes, std::uint32_t value) {
  for (int shift = 0; shift < 32; shift += 8) {
    bytes->push_back(static_cast<std::uint8_t>((value >> shift) & 0xff));
  }
}

void append_u64(std::vector<std::uint8_t>* bytes, std::uint64_t value) {
  for (int shift = 0; shift < 64; shift += 8) {
    bytes->push_back(static_cast<std::uint8_t>((value >> shift) & 0xff));
  }
}

std::uint16_t read_u16(const std::array<std::uint8_t, kHeaderBytes>& bytes,
                       std::size_t offset) {
  return static_cast<std::uint16_t>(bytes[offset]) |
         (static_cast<std::uint16_t>(bytes[offset + 1]) << 8);
}

std::uint32_t read_u32(const std::array<std::uint8_t, kHeaderBytes>& bytes,
                       std::size_t offset) {
  std::uint32_t value = 0;
  for (int index = 0; index < 4; ++index) {
    value |= static_cast<std::uint32_t>(bytes[offset + index]) << (index * 8);
  }
  return value;
}

std::uint64_t read_u64(const std::array<std::uint8_t, kHeaderBytes>& bytes,
                       std::size_t offset) {
  std::uint64_t value = 0;
  for (int index = 0; index < 8; ++index) {
    value |= static_cast<std::uint64_t>(bytes[offset + index]) << (index * 8);
  }
  return value;
}

bool write_exact(HANDLE pipe, const std::uint8_t* bytes, std::size_t size) {
  while (size > 0) {
    const DWORD chunk = static_cast<DWORD>(
        (std::min)(size, static_cast<std::size_t>(MAXDWORD)));
    DWORD written = 0;
    if (!WriteFile(pipe, bytes, chunk, &written, nullptr) || written == 0) {
      return false;
    }
    bytes += written;
    size -= written;
  }
  return true;
}

bool read_exact(HANDLE pipe, HANDLE process, std::uint8_t* bytes,
                std::size_t size) {
  const ULONGLONG deadline = GetTickCount64() + kPipeReadTimeoutMilliseconds;
  while (size > 0) {
    const DWORD chunk = static_cast<DWORD>(
        (std::min)(size, static_cast<std::size_t>(MAXDWORD)));
    DWORD received = 0;
    const BOOL read_succeeded =
        ReadFile(pipe, bytes, chunk, &received, nullptr);
    if (read_succeeded && received > 0) {
      bytes += received;
      size -= received;
      continue;
    }
    const DWORD error = read_succeeded ? ERROR_NO_DATA : GetLastError();
    if ((error != ERROR_NO_DATA && error != ERROR_PIPE_LISTENING) ||
        WaitForSingleObject(process, 0) == WAIT_OBJECT_0 ||
        GetTickCount64() >= deadline) {
      return false;
    }
    Sleep(5);
  }
  return true;
}

bool write_frame(HANDLE pipe, const Frame& frame) {
  if (frame.payload.size() > kMaximumPayloadBytes) {
    return false;
  }
  std::vector<std::uint8_t> bytes;
  bytes.reserve(kHeaderBytes + frame.payload.size());
  append_u32(&bytes, kProtocolMagic);
  append_u16(&bytes, kProtocolVersion);
  append_u16(&bytes, static_cast<std::uint16_t>(frame.opcode));
  append_u64(&bytes, frame.request_id);
  append_u32(&bytes, static_cast<std::uint32_t>(frame.payload.size()));
  bytes.insert(bytes.end(), frame.payload.begin(), frame.payload.end());
  return write_exact(pipe, bytes.data(), bytes.size());
}

bool read_frame(HANDLE pipe, HANDLE process, Frame* frame) {
  std::array<std::uint8_t, kHeaderBytes> header{};
  if (!read_exact(pipe, process, header.data(), header.size()) ||
      read_u32(header, 0) != kProtocolMagic ||
      read_u16(header, 4) != kProtocolVersion) {
    return false;
  }
  const std::uint32_t payload_size = read_u32(header, 16);
  if (payload_size > kMaximumPayloadBytes) {
    return false;
  }
  frame->opcode = static_cast<Opcode>(read_u16(header, 6));
  frame->request_id = read_u64(header, 8);
  frame->payload.assign(payload_size, 0);
  return frame->payload.empty() ||
         read_exact(pipe, process, frame->payload.data(), frame->payload.size());
}

bool random_bytes(std::uint8_t* bytes, std::size_t size) {
  return BCryptGenRandom(nullptr, bytes, static_cast<ULONG>(size),
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
}

std::wstring hexadecimal(const std::uint8_t* bytes, std::size_t size) {
  constexpr wchar_t kHex[] = L"0123456789abcdef";
  std::wstring output;
  output.reserve(size * 2);
  for (std::size_t index = 0; index < size; ++index) {
    output.push_back(kHex[(bytes[index] >> 4) & 0x0f]);
    output.push_back(kHex[bytes[index] & 0x0f]);
  }
  return output;
}

bool current_user_sid(std::wstring* sid) {
  ScopedHandle token;
  HANDLE raw_token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw_token)) {
    return false;
  }
  token.reset(raw_token);
  DWORD required = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &required);
  if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }
  std::vector<std::uint8_t> information(required);
  if (!GetTokenInformation(token.get(), TokenUser, information.data(), required,
                           &required)) {
    return false;
  }
  const auto* user = reinterpret_cast<const TOKEN_USER*>(information.data());
  LPWSTR sid_text = nullptr;
  if (!ConvertSidToStringSidW(user->User.Sid, &sid_text)) {
    return false;
  }
  LocalPointer owned_sid(sid_text);
  *sid = sid_text;
  return true;
}

bool create_user_only_security_attributes(SECURITY_ATTRIBUTES* attributes,
                                          LocalPointer* descriptor) {
  std::wstring sid;
  if (!current_user_sid(&sid)) {
    return false;
  }
  // Protected DACL: only the current user receives full pipe access.
  const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")";
  PSECURITY_DESCRIPTOR raw_descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &raw_descriptor, nullptr)) {
    return false;
  }
  descriptor->reset(raw_descriptor);
  attributes->nLength = sizeof(*attributes);
  attributes->lpSecurityDescriptor = descriptor->get();
  attributes->bInheritHandle = FALSE;
  return true;
}

std::vector<wchar_t> child_environment(const std::wstring& token) {
  std::vector<std::wstring> entries;
  LPWCH inherited = GetEnvironmentStringsW();
  if (inherited != nullptr) {
    for (const wchar_t* entry = inherited; *entry != L'\0';) {
      const std::size_t length = std::wcslen(entry);
      if (_wcsnicmp(entry, kTokenEnvironmentKey,
                    std::size(kTokenEnvironmentKey) - 1) != 0 ||
          entry[std::size(kTokenEnvironmentKey) - 1] != L'=') {
        entries.emplace_back(entry, length);
      }
      entry += length + 1;
    }
    FreeEnvironmentStringsW(inherited);
  }
  const std::wstring token_entry =
      std::wstring(kTokenEnvironmentKey) + L"=" + token;
  entries.push_back(token_entry);
  std::sort(entries.begin(), entries.end(), [](const std::wstring& left,
                                                const std::wstring& right) {
    return _wcsicmp(left.c_str(), right.c_str()) < 0;
  });

  std::vector<wchar_t> environment;
  for (const auto& entry : entries) {
    environment.insert(environment.end(), entry.begin(), entry.end());
    environment.push_back(L'\0');
  }
  environment.push_back(L'\0');
  return environment;
}

bool wait_for_pipe_connection(HANDLE pipe, HANDLE process) {
  const ULONGLONG deadline =
      GetTickCount64() + kPipeConnectTimeoutMilliseconds;
  while (GetTickCount64() < deadline) {
    if (ConnectNamedPipe(pipe, nullptr)) {
      return true;
    }
    const DWORD error = GetLastError();
    if (error == ERROR_PIPE_CONNECTED) {
      return true;
    }
    if (error != ERROR_PIPE_LISTENING ||
        WaitForSingleObject(process, 0) == WAIT_OBJECT_0) {
      return false;
    }
    Sleep(10);
  }
  return false;
}

bool pipe_client_matches_process(HANDLE pipe, DWORD expected_process_id) {
  ULONG client_process_id = 0;
  return GetNamedPipeClientProcessId(pipe, &client_process_id) != FALSE &&
         client_process_id == expected_process_id;
}

bool launch_helper(const std::filesystem::path& helper_executable,
                   const std::wstring& request_pipe_name,
                   const std::wstring& response_pipe_name,
                   const std::wstring& token,
                   PROCESS_INFORMATION* process_information) {
  if (!std::filesystem::is_regular_file(helper_executable)) {
    return false;
  }
  std::wstring command_line = L"\"" + helper_executable.wstring() +
                              L"\" --request-pipe \"" + request_pipe_name +
                              L"\" --response-pipe \"" + response_pipe_name +
                              L"\" --idle-timeout-ms " +
                              std::to_wstring(kProbeHelperIdleTimeoutMilliseconds);
  std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
  mutable_command.push_back(L'\0');
  auto environment = child_environment(token);
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  return CreateProcessW(helper_executable.c_str(), mutable_command.data(), nullptr,
                        nullptr, FALSE,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                        environment.data(), helper_executable.parent_path().c_str(),
                        &startup, process_information) != FALSE;
}

bool expect(HANDLE pipe, HANDLE process, Opcode opcode,
            std::uint64_t request_id) {
  Frame frame;
  return read_frame(pipe, process, &frame) && frame.opcode == opcode &&
         frame.request_id == request_id;
}

std::vector<std::uint8_t> little_endian_u32(std::uint32_t value) {
  std::vector<std::uint8_t> bytes;
  append_u32(&bytes, value);
  return bytes;
}

std::vector<std::uint8_t> little_endian_u64(std::uint64_t value) {
  std::vector<std::uint8_t> bytes;
  append_u64(&bytes, value);
  return bytes;
}

bool run_probe_session(const std::filesystem::path& helper_executable,
                       bool terminate_after_health) {
  std::array<std::uint8_t, 32> token{};
  std::array<std::uint8_t, 8> pipe_nonce{};
  if (!random_bytes(token.data(), token.size()) ||
      !random_bytes(pipe_nonce.data(), pipe_nonce.size())) {
    return false;
  }
  const std::wstring pipe_base =
      L"\\\\.\\pipe\\PrivatePinyinAI-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" +
      hexadecimal(pipe_nonce.data(), pipe_nonce.size());
  const std::wstring request_pipe_name = pipe_base + L"-request";
  const std::wstring response_pipe_name = pipe_base + L"-response";

  SECURITY_ATTRIBUTES security_attributes{};
  LocalPointer security_descriptor;
  if (!create_user_only_security_attributes(&security_attributes,
                                             &security_descriptor)) {
    return false;
  }
  // Use separate unidirectional pipe objects so a blocking helper read cannot
  // serialize and starve its response writer on the same synchronous pipe.
  ScopedHandle request_pipe(CreateNamedPipeW(
      request_pipe_name.c_str(),
      PIPE_ACCESS_OUTBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      1, static_cast<DWORD>(kMaximumPayloadBytes),
      static_cast<DWORD>(kMaximumPayloadBytes), 0, &security_attributes));
  ScopedHandle response_pipe(CreateNamedPipeW(
      response_pipe_name.c_str(),
      PIPE_ACCESS_INBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      1, static_cast<DWORD>(kMaximumPayloadBytes),
      static_cast<DWORD>(kMaximumPayloadBytes), 0, &security_attributes));
  if (!request_pipe.valid() || !response_pipe.valid()) {
    return false;
  }

  PROCESS_INFORMATION process_information{};
  if (!launch_helper(helper_executable, request_pipe_name, response_pipe_name,
                     hexadecimal(token.data(), token.size()),
                     &process_information)) {
    return false;
  }
  ScopedHandle process(process_information.hProcess);
  ScopedHandle thread(process_information.hThread);
  if (!wait_for_pipe_connection(request_pipe.get(), process.get()) ||
      !wait_for_pipe_connection(response_pipe.get(), process.get()) ||
      !pipe_client_matches_process(request_pipe.get(),
                                   process_information.dwProcessId) ||
      !pipe_client_matches_process(response_pipe.get(),
                                   process_information.dwProcessId)) {
    TerminateProcess(process.get(), 1);
    return false;
  }
  bool ok = write_frame(
                request_pipe.get(),
                Frame{Opcode::kAuthenticate, 0,
                      std::vector<std::uint8_t>(token.begin(), token.end())}) &&
            expect(response_pipe.get(), process.get(), Opcode::kAuthenticated,
                   0) &&
            write_frame(request_pipe.get(), Frame{Opcode::kHealth, 1, {}}) &&
            expect(response_pipe.get(), process.get(), Opcode::kHealthy, 1);

  if (terminate_after_health) {
    if (!TerminateProcess(process.get(), 77)) {
      ok = false;
    }
    if (WaitForSingleObject(process.get(), 2000) != WAIT_OBJECT_0) {
      ok = false;
    }
    DisconnectNamedPipe(request_pipe.get());
    DisconnectNamedPipe(response_pipe.get());
    return ok;
  }

  ok = ok &&
       write_frame(request_pipe.get(), Frame{Opcode::kMockInference, 2,
                                             little_endian_u32(500)}) &&
       write_frame(request_pipe.get(),
                   Frame{Opcode::kCancel, 3, little_endian_u64(2)}) &&
       expect(response_pipe.get(), process.get(), Opcode::kCancelled, 2) &&
       expect(response_pipe.get(), process.get(), Opcode::kAcknowledged, 3) &&
       write_frame(request_pipe.get(), Frame{Opcode::kShutdown, 4, {}}) &&
       expect(response_pipe.get(), process.get(), Opcode::kAcknowledged, 4);

  if (WaitForSingleObject(process.get(), 2000) != WAIT_OBJECT_0) {
    TerminateProcess(process.get(), 1);
    WaitForSingleObject(process.get(), 2000);
    ok = false;
  }
  DisconnectNamedPipe(request_pipe.get());
  DisconnectNamedPipe(response_pipe.get());
  return ok;
}

}  // namespace

bool AiHelperClient::run_mock_probe(
    const std::filesystem::path& helper_executable) {
  return run_probe_session(helper_executable, true) &&
         run_probe_session(helper_executable, false);
}

}  // namespace private_pinyin
