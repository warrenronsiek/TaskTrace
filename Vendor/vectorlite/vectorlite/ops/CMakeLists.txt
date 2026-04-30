find_package(hwy CONFIG REQUIRED)

find_path(HIGHWAY_INCLUDE_DIRS hwy/highway.h)
message(STATUS "Highway include dir: ${HIGHWAY_INCLUDE_DIRS}")

add_library(ops STATIC ops.cpp)
target_link_libraries(ops PRIVATE hwy::hwy)
target_include_directories(ops PRIVATE ${HIGHWAY_INCLUDE_DIRS} ${CMAKE_CURRENT_LIST_DIR})
# target_compile_definitions(ops PRIVATE HWY_IDE=1)

if(VECTORLITE_BUILD_TESTS)
    include(GoogleTest)
    enable_testing()

    add_executable(ops_test ops_test.cpp)
    target_include_directories(ops PRIVATE ${HIGHWAY_INCLUDE_DIRS} ${CMAKE_CURRENT_LIST_DIR})
    target_link_libraries(ops_test PRIVATE ops GTest::gtest GTest::gtest_main)

    gtest_discover_tests(ops_test)

    add_test(NAME ops_test COMMAND ops_test)
endif()

if(VECTORLITE_BUILD_BENCHMARKS)
    add_executable(ops_benchmark ops_benchmark.cpp)
    target_include_directories(ops_benchmark PRIVATE ${CMAKE_CURRENT_LIST_DIR})
    target_link_libraries(ops_benchmark PRIVATE ops benchmark::benchmark benchmark::benchmark_main)
endif()

if (MSVC)
    if(VECTORLITE_BUILD_TESTS)
        target_compile_options(ops_test PRIVATE /arch:AVX)
    endif()
    if(VECTORLITE_BUILD_BENCHMARKS)
        target_compile_options(ops_benchmark PRIVATE /arch:AVX)
    endif()
else()
    # Fixes compilation on Linux. libops will be linked into vectorlite.so, so -fPIC is needed.
    target_compile_options(ops PRIVATE -fPIC)
    if(VECTORLITE_BUILD_TESTS)
        target_compile_options(ops_test PRIVATE -march=native)
    endif()
    if(VECTORLITE_BUILD_BENCHMARKS)
        target_compile_options(ops_benchmark PRIVATE -march=native)
    endif()
endif()
