cmake_minimum_required(VERSION 3.10)
project(dart_not_native)

# Specify the C standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Add the library
add_library(bridge SHARED
    src/main/cpp/bridge.c
)

# Specify the include directories
target_include_directories(bridge PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
)
