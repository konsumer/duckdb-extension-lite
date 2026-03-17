cmake_minimum_required(VERSION 3.20)
project(duckdb_extension_quack CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# -- Configuration -----------------------------------------------------------
set(DUCKDB_VERSION "v1.5.0" CACHE STRING "DuckDB version to build against")
set(EXTENSION_NAME "quack" CACHE STRING "Extension name")
set(EXTENSION_VERSION "" CACHE STRING "Extension version string (optional)")

# Extension source files - add your .cpp files here
set(EXTENSION_SOURCES
    src/quack_extension.cpp
)

# -- Detect platform string for DuckDB extension footer ----------------------
if(APPLE)
    if(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
        set(DUCKDB_PLATFORM "osx_amd64")
    elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
        set(DUCKDB_PLATFORM "osx_arm64")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
        set(DUCKDB_PLATFORM "osx_arm64")
    else()
        set(DUCKDB_PLATFORM "osx_amd64")
    endif()
elseif(WIN32)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set(DUCKDB_PLATFORM "windows_arm64")
    else()
        set(DUCKDB_PLATFORM "windows_amd64")
    endif()
else()
    # Linux
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
        set(DUCKDB_PLATFORM "linux_amd64")  # will be overridden below
        set(DUCKDB_PLATFORM "linux_arm64")
    else()
        set(DUCKDB_PLATFORM "linux_amd64")
    endif()
endif()

# Allow manual override
set(DUCKDB_PLATFORM "${DUCKDB_PLATFORM}" CACHE STRING "DuckDB platform string (auto-detected)")

message(STATUS "DuckDB version:  ${DUCKDB_VERSION}")
message(STATUS "DuckDB platform: ${DUCKDB_PLATFORM}")
message(STATUS "Extension name:  ${EXTENSION_NAME}")

# -- Download DuckDB headers (amalgamated source) ----------------------------
set(DUCKDB_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_duckdb")
set(DUCKDB_SRC_ZIP "${DUCKDB_DOWNLOAD_DIR}/libduckdb-src.zip")
set(DUCKDB_SRC_DIR "${DUCKDB_DOWNLOAD_DIR}/src")

set(DUCKDB_SRC_URL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-src.zip")

if(NOT EXISTS "${DUCKDB_SRC_DIR}/duckdb.hpp")
    message(STATUS "Downloading DuckDB source headers from ${DUCKDB_SRC_URL}")
    file(DOWNLOAD "${DUCKDB_SRC_URL}" "${DUCKDB_SRC_ZIP}"
         STATUS download_status
         SHOW_PROGRESS)
    list(GET download_status 0 download_code)
    if(NOT download_code EQUAL 0)
        list(GET download_status 1 download_msg)
        message(FATAL_ERROR "Failed to download DuckDB source: ${download_msg}")
    endif()
    file(ARCHIVE_EXTRACT INPUT "${DUCKDB_SRC_ZIP}" DESTINATION "${DUCKDB_SRC_DIR}")
endif()

# -- Download footer script --------------------------------------------------
set(FOOTER_SCRIPT "${DUCKDB_DOWNLOAD_DIR}/add_duckdb_extension_footer.py")
set(FOOTER_SCRIPT_URL "https://gist.githubusercontent.com/konsumer/418053db631cd76d1856367672622636/raw/998ab6a524fb0a4cdf00f83a77135e443bf43537/add_duckdb_extension_footer.py")

if(NOT EXISTS "${FOOTER_SCRIPT}")
    message(STATUS "Downloading extension footer script")
    file(DOWNLOAD "${FOOTER_SCRIPT_URL}" "${FOOTER_SCRIPT}"
         STATUS download_status)
    list(GET download_status 0 download_code)
    if(NOT download_code EQUAL 0)
        message(FATAL_ERROR "Failed to download footer script")
    endif()
endif()

# -- Build the extension shared library --------------------------------------
add_library(${EXTENSION_NAME}_loadable MODULE ${EXTENSION_SOURCES})

target_include_directories(${EXTENSION_NAME}_loadable PRIVATE "${DUCKDB_SRC_DIR}")
target_compile_definitions(${EXTENSION_NAME}_loadable PRIVATE
    DUCKDB_BUILD_LOADABLE_EXTENSION
)

if(EXTENSION_VERSION)
    string(TOUPPER ${EXTENSION_NAME} EXT_NAME_UPPER)
    target_compile_definitions(${EXTENSION_NAME}_loadable PRIVATE
        "EXT_VERSION_${EXT_NAME_UPPER}=\"${EXTENSION_VERSION}\""
    )
endif()

# Platform-specific shared library settings
if(APPLE)
    set_target_properties(${EXTENSION_NAME}_loadable PROPERTIES
        SUFFIX ".duckdb_extension"
        PREFIX ""
        # Extensions are loaded into duckdb which already has all symbols
        LINK_FLAGS "-undefined dynamic_lookup"
    )
elseif(WIN32)
    set_target_properties(${EXTENSION_NAME}_loadable PROPERTIES
        SUFFIX ".duckdb_extension"
        PREFIX ""
    )
else()
    # On Linux, link against libduckdb.so so symbols are resolved at load time.
    # Download it from releases if not already present.
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
        set(_LIBDUCKDB_ARCH "linux-arm64")
    else()
        set(_LIBDUCKDB_ARCH "linux-amd64")
    endif()
    set(LIBDUCKDB_ZIP "${DUCKDB_DOWNLOAD_DIR}/libduckdb-${_LIBDUCKDB_ARCH}.zip")
    set(LIBDUCKDB_DIR "${DUCKDB_DOWNLOAD_DIR}/libduckdb")

    if(NOT EXISTS "${LIBDUCKDB_DIR}/libduckdb.so")
        set(LIBDUCKDB_URL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-${_LIBDUCKDB_ARCH}.zip")
        message(STATUS "Downloading libduckdb from ${LIBDUCKDB_URL}")
        file(DOWNLOAD "${LIBDUCKDB_URL}" "${LIBDUCKDB_ZIP}"
             STATUS download_status SHOW_PROGRESS)
        list(GET download_status 0 download_code)
        if(NOT download_code EQUAL 0)
            message(FATAL_ERROR "Failed to download libduckdb")
        endif()
        file(ARCHIVE_EXTRACT INPUT "${LIBDUCKDB_ZIP}" DESTINATION "${LIBDUCKDB_DIR}")
    endif()

    # Create an imported target for libduckdb
    add_library(duckdb_lib SHARED IMPORTED)
    set_target_properties(duckdb_lib PROPERTIES IMPORTED_LOCATION "${LIBDUCKDB_DIR}/libduckdb.so")

    set_target_properties(${EXTENSION_NAME}_loadable PROPERTIES
        SUFFIX ".duckdb_extension"
        PREFIX ""
    )
    target_link_libraries(${EXTENSION_NAME}_loadable PRIVATE duckdb_lib)
endif()

set_target_properties(${EXTENSION_NAME}_loadable PROPERTIES
    OUTPUT_NAME "${EXTENSION_NAME}"
)

# -- Append DuckDB extension footer after build ------------------------------
find_package(Python3 COMPONENTS Interpreter QUIET)
if(NOT Python3_FOUND)
    find_program(PYTHON_EXE NAMES python3 python)
    if(NOT PYTHON_EXE)
        message(FATAL_ERROR "Python 3 is required to append the extension footer")
    endif()
else()
    set(PYTHON_EXE "${Python3_EXECUTABLE}")
endif()

set(EXT_OUTPUT "$<TARGET_FILE:${EXTENSION_NAME}_loadable>")

add_custom_command(
    TARGET ${EXTENSION_NAME}_loadable POST_BUILD
    COMMAND "${PYTHON_EXE}" "${FOOTER_SCRIPT}" "${EXT_OUTPUT}" "${DUCKDB_VERSION}" "${DUCKDB_PLATFORM}" "${EXTENSION_VERSION}"
    COMMENT "Appending DuckDB extension footer (platform=${DUCKDB_PLATFORM}, version=${DUCKDB_VERSION})"
    VERBATIM
)

# -- Convenience: copy to build root for easy loading ------------------------
add_custom_command(
    TARGET ${EXTENSION_NAME}_loadable POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${EXT_OUTPUT}" "${CMAKE_BINARY_DIR}/${EXTENSION_NAME}.duckdb_extension"
    COMMENT "Copying extension to ${CMAKE_BINARY_DIR}/${EXTENSION_NAME}.duckdb_extension"
    VERBATIM
)

message(STATUS "Extension will be built at: ${CMAKE_BINARY_DIR}/${EXTENSION_NAME}.duckdb_extension")
