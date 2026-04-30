cmake_minimum_required(VERSION 3.22 FATAL_ERROR)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" VECTORLITE_VERSION)

if (WIN32)
    set(VCPKG_TARGET_TRIPLET "x64-windows-static-md-release")
    message(STATUS "VCPKG_TARGET_TRIPLET on windows: ${VCPKG_TARGET_TRIPLET}")
endif(WIN32)

project(vectorlite VERSION ${VECTORLITE_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(VECTORLITE_BUILD_TESTS "Build vectorlite unit tests" OFF)
option(VECTORLITE_BUILD_BENCHMARKS "Build vectorlite benchmarks" OFF)

set(VECTORLITE_SQLITE_INCLUDE_DIR "" CACHE PATH "Directory containing sqlite3.h and sqlite3ext.h for extension builds")

find_package(absl CONFIG REQUIRED)
find_package(RapidJSON CONFIG REQUIRED)
find_package(hnswlib CONFIG REQUIRED)
find_package(re2 CONFIG REQUIRED)
if(VECTORLITE_BUILD_TESTS)
    find_package(GTest CONFIG REQUIRED)
endif()
if(VECTORLITE_BUILD_BENCHMARKS)
    find_package(benchmark CONFIG REQUIRED)
endif()

find_path(RAPIDJSON_INCLUDE_DIRS rapidjson/rapidjson.h)
message(STATUS "RapidJSON include dir: ${RAPIDJSON_INCLUDE_DIRS}")
find_path(HNSWLIB_INCLUDE_DIRS hnswlib/hnswlib.h)
message(STATUS "HNSWLIB include dir: ${HNSWLIB_INCLUDE_DIRS}")

if(NOT VECTORLITE_SQLITE_INCLUDE_DIR)
    message(FATAL_ERROR "VECTORLITE_SQLITE_INCLUDE_DIR must point at sqlite3.h and sqlite3ext.h for extension builds.")
endif()

# Set up install directory for scikit-build-core
if(SKBUILD)
    # Don't override CMAKE_INSTALL_PREFIX - let scikit-build-core manage it
    # We'll install to vectorlite_py subdirectory in the vectorlite/CMakeLists.txt
endif()

add_subdirectory(vectorlite)
