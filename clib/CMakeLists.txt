cmake_minimum_required(VERSION 3.10)
project(foo_headless_embedder C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Auto-detect platform/arch and set appropriate library name/path
if(WIN32)
  set(FLUTTER_ENGINE_LIB_NAME "flutter_engine.dll")
  set(FLUTTER_PLATFORM_DIR "windows-x64")
elseif(APPLE)
  set(FLUTTER_ENGINE_LIB_NAME "libflutter_engine.dylib")
  if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    set(FLUTTER_PLATFORM_DIR "macos-arm64")
  else()
    set(FLUTTER_PLATFORM_DIR "macos-x64")
  endif()
else()
  set(FLUTTER_ENGINE_LIB_NAME "libflutter_engine.so")
  set(FLUTTER_PLATFORM_DIR "linux-x64")
endif()

# Default to looking for the engine library in build/{os-arch}/
# Override from the command line: -DFLUTTER_ENGINE_LIB=/abs/path/libflutter_engine.{so|dylib|dll}
set(FLUTTER_ENGINE_LIB "${CMAKE_CURRENT_LIST_DIR}/build/${FLUTTER_PLATFORM_DIR}/${FLUTTER_ENGINE_LIB_NAME}" CACHE FILEPATH "Path to flutter engine library.")

if(NOT EXISTS "${FLUTTER_ENGINE_LIB}")
  message(FATAL_ERROR "Flutter engine library not found at: ${FLUTTER_ENGINE_LIB}\nSet FLUTTER_ENGINE_LIB to your flutter engine library (.so/.dylib/.dll)")
endif()

message(STATUS "Using Flutter engine: ${FLUTTER_ENGINE_LIB}")

add_executable(embedder main.c)

target_include_directories(embedder
  PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
)

target_link_libraries(embedder
  PRIVATE
    ${FLUTTER_ENGINE_LIB}
)

if(WIN32)
  # Windows: No additional libraries needed (threading is in kernel32)
elseif(APPLE)
  # macOS: pthread is needed, libdl is not
  target_link_libraries(embedder PRIVATE pthread)
else()
  # Linux: pthread and dl are needed
  target_link_libraries(embedder PRIVATE pthread dl)
endif()

# Ensure the engine library can be located at runtime next to the executable.
if(WIN32)
  # Windows finds DLLs in the executable directory by default
elseif(APPLE)
  set_target_properties(embedder PROPERTIES
    INSTALL_RPATH "@loader_path"
    BUILD_WITH_INSTALL_RPATH TRUE
  )
else()
  set_target_properties(embedder PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH TRUE
  )
endif()