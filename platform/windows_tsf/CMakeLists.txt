cmake_minimum_required(VERSION 3.24)

project(PrivatePinyinTsf LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "PrivatePinyinTsf is a Windows TSF DLL and must be built on Windows.")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(PrivatePinyinTsf SHARED
  PrivatePinyinTsf.def
  src/candidate_window.cpp
  src/class_factory.cpp
  src/core_bridge.cpp
  src/dllmain.cpp
  src/key_map.cpp
  src/registration.cpp
  src/text_service.cpp
)

target_include_directories(PrivatePinyinTsf PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/../../ffi
)

target_compile_definitions(PrivatePinyinTsf PRIVATE
  NOMINMAX
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
)

if(MSVC)
  target_compile_options(PrivatePinyinTsf PRIVATE /utf-8)
endif()

if(DEFINED PRIVATE_PINYIN_IME_LIB AND NOT "${PRIVATE_PINYIN_IME_LIB}" STREQUAL "")
  target_link_libraries(PrivatePinyinTsf PRIVATE "${PRIVATE_PINYIN_IME_LIB}")
else()
  message(WARNING "PRIVATE_PINYIN_IME_LIB is not set; configure with -DPRIVATE_PINYIN_IME_LIB=<path-to-private_pinyin_ime.lib>.")
endif()

target_link_libraries(PrivatePinyinTsf PRIVATE
  advapi32
  gdi32
  ole32
  user32
  uuid
)

set_target_properties(PrivatePinyinTsf PROPERTIES
  OUTPUT_NAME "PrivatePinyinTsf"
)
