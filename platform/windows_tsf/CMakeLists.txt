cmake_minimum_required(VERSION 3.24)

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

project(PrivatePinyinTsf LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "PrivatePinyinTsf is a Windows TSF DLL and must be built on Windows.")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_library(PrivatePinyinTsf SHARED
  PrivatePinyinTsf.def
  src/ai_helper_client.cpp
  src/candidate_window.cpp
  src/class_factory.cpp
  src/core_bridge.cpp
  src/dllmain.cpp
  src/key_map.cpp
  src/registration.cpp
  src/text_service.cpp
)

add_executable(PrivatePinyinAIHelperProbe
  src/ai_helper_client.cpp
  src/ai_helper_probe_main.cpp
)

target_include_directories(PrivatePinyinTsf PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/../../ffi
)

target_include_directories(PrivatePinyinAIHelperProbe PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_compile_definitions(PrivatePinyinTsf PRIVATE
  NOMINMAX
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
)

target_compile_definitions(PrivatePinyinAIHelperProbe PRIVATE
  NOMINMAX
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
)

if(MSVC)
  target_compile_options(PrivatePinyinTsf PRIVATE /utf-8)
  target_compile_options(PrivatePinyinAIHelperProbe PRIVATE /utf-8)
endif()

if(DEFINED PRIVATE_PINYIN_IME_LIB AND NOT "${PRIVATE_PINYIN_IME_LIB}" STREQUAL "")
  target_link_libraries(PrivatePinyinTsf PRIVATE "${PRIVATE_PINYIN_IME_LIB}")
else()
  message(WARNING "PRIVATE_PINYIN_IME_LIB is not set; configure with -DPRIVATE_PINYIN_IME_LIB=<path-to-private_pinyin_ime.lib>.")
endif()

target_link_libraries(PrivatePinyinTsf PRIVATE
  advapi32
  bcrypt
  gdi32
  ole32
  oleaut32
  shell32
  user32
  uuid
)

target_link_libraries(PrivatePinyinAIHelperProbe PRIVATE
  advapi32
  bcrypt
)

set_target_properties(PrivatePinyinTsf PROPERTIES
  OUTPUT_NAME "PrivatePinyinTsf"
)
