#include <filesystem>

#include "ai_helper_client.h"

int wmain(int argument_count, wchar_t** arguments) {
  if (argument_count != 2) {
    return 2;
  }
  return private_pinyin::AiHelperClient::run_mock_probe(
             std::filesystem::path(arguments[1]))
             ? 0
             : 1;
}
