include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(k_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(k_setup_options)
  option(k_ENABLE_HARDENING "Enable hardening" ON)
  option(k_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    k_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    k_ENABLE_HARDENING
    OFF)

  k_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR k_PACKAGING_MAINTAINER_MODE)
    option(k_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(k_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(k_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(k_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(k_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(k_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(k_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(k_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(k_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(k_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(k_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(k_ENABLE_PCH "Enable precompiled headers" OFF)
    option(k_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(k_ENABLE_IPO "Enable IPO/LTO" ON)
    option(k_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(k_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(k_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(k_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(k_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(k_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(k_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(k_ENABLE_UNITY_BUILD "Enable unity builds" ON)
    option(k_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(k_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(k_ENABLE_PCH "Enable precompiled headers" OFF)
    option(k_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      k_ENABLE_IPO
      k_WARNINGS_AS_ERRORS
      k_ENABLE_USER_LINKER
      k_ENABLE_SANITIZER_ADDRESS
      k_ENABLE_SANITIZER_LEAK
      k_ENABLE_SANITIZER_UNDEFINED
      k_ENABLE_SANITIZER_THREAD
      k_ENABLE_SANITIZER_MEMORY
      k_ENABLE_UNITY_BUILD
      k_ENABLE_CLANG_TIDY
      k_ENABLE_CPPCHECK
      k_ENABLE_COVERAGE
      k_ENABLE_PCH
      k_ENABLE_CACHE)
  endif()

  k_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (k_ENABLE_SANITIZER_ADDRESS OR k_ENABLE_SANITIZER_THREAD OR k_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(k_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(k_global_options)
  if(k_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    k_enable_ipo()
  endif()

  k_supports_sanitizers()

  if(k_ENABLE_HARDENING AND k_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR k_ENABLE_SANITIZER_UNDEFINED
       OR k_ENABLE_SANITIZER_ADDRESS
       OR k_ENABLE_SANITIZER_THREAD
       OR k_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${k_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${k_ENABLE_SANITIZER_UNDEFINED}")
    k_enable_hardening(k_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(k_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(k_warnings INTERFACE)
  add_library(k_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  k_set_project_warnings(
    k_warnings
    ${k_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(k_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(k_options)
  endif()

  include(cmake/Sanitizers.cmake)
  k_enable_sanitizers(
    k_options
    ${k_ENABLE_SANITIZER_ADDRESS}
    ${k_ENABLE_SANITIZER_LEAK}
    ${k_ENABLE_SANITIZER_UNDEFINED}
    ${k_ENABLE_SANITIZER_THREAD}
    ${k_ENABLE_SANITIZER_MEMORY})

  set_target_properties(k_options PROPERTIES UNITY_BUILD ${k_ENABLE_UNITY_BUILD})

  if(k_ENABLE_PCH)
    target_precompile_headers(
      k_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(k_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    k_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(k_ENABLE_CLANG_TIDY)
    k_enable_clang_tidy(k_options ${k_WARNINGS_AS_ERRORS})
  endif()

  if(k_ENABLE_CPPCHECK)
    k_enable_cppcheck(${k_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(k_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    k_enable_coverage(k_options)
  endif()

  if(k_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(k_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(k_ENABLE_HARDENING AND NOT k_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR k_ENABLE_SANITIZER_UNDEFINED
       OR k_ENABLE_SANITIZER_ADDRESS
       OR k_ENABLE_SANITIZER_THREAD
       OR k_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    k_enable_hardening(k_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
