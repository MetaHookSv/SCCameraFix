cmake_minimum_required(VERSION 3.21)
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
project(SCCameraFix LANGUAGES CXX)

if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "SCCameraFix requires Windows MSVC x86. Configure with -A Win32.")
endif()
get_property(multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(multi_config)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "Supported configurations" FORCE)
elseif(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release)$")
    message(FATAL_ERROR "Select Debug or Release.")
endif()

include(cmake/Dependencies.cmake)
sccamerafix_prepare_dependencies()

include("${VC_LTL_Root}/VC-LTL helper for cmake.cmake")

# Include directories follow SCCameraFix.vcxproj. Unlike HeapPatch the plugin
# touches no SourceSDK and no Capstone header, so neither is added.
add_library(sccamerafix_settings INTERFACE)
target_include_directories(sccamerafix_settings INTERFACE
    src
    "${METAHOOK_SOURCE_PATH}/include"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/cl_dll"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/common"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/engine"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/pm_shared"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/public"
    "${METAHOOK_SOURCE_PATH}/include/Interface"
)
# _MBCS mirrors the original MultiByte character set.
target_compile_definitions(sccamerafix_settings INTERFACE WIN32 _WINDOWS _USRDLL _MBCS
    $<$<CONFIG:Debug>:_DEBUG>
    $<$<CONFIG:Release>:NDEBUG>)
# Debug used to turn every warning off, Release stayed at Level3; the vcxproj
# suppressed the SDK's known warnings in every configuration.
target_compile_options(sccamerafix_settings INTERFACE /permissive
    $<$<CONFIG:Debug>:/W0>
    $<$<CONFIG:Release>:/W3>
    /wd4311 /wd4312 /wd4819 /wd4996)

include(cmake/Sources.cmake)
add_library(SCCameraFix SHARED ${SCCAMERAFIX_SOURCES})
target_link_libraries(SCCameraFix PRIVATE sccamerafix_settings)
target_compile_options(SCCameraFix PRIVATE /MP /Zi)
target_link_options(SCCameraFix PRIVATE /DEBUG /SUBSYSTEM:WINDOWS
    $<$<CONFIG:Debug>:/INCREMENTAL>
    $<$<CONFIG:Release>:/INCREMENTAL:NO>
    $<$<CONFIG:Release>:/OPT:REF>
    $<$<CONFIG:Release>:/OPT:ICF>)
set_target_properties(SCCameraFix PROPERTIES INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

install(TARGETS SCCameraFix RUNTIME DESTINATION svencoop/metahook/plugins)
install(FILES "$<TARGET_PDB_FILE:SCCameraFix>" DESTINATION svencoop/metahook/plugins)

# SCCameraFix ships its own gamedata catalog, pruned to the client symbols it
# resolves, in a nested directory the launcher's catalog loader merges
# (metahook/gamedata/sccamerafix). The manifest lists those symbols.
option(SCCAMERAFIX_SYNC_GAMEDATA "Download and prune SCCameraFix's gamedata catalog before building" ON)
set(SCCAMERAFIX_GAMEDATA_DIR "${PROJECT_BINARY_DIR}/assets/svencoop/metahook/gamedata/sccamerafix" CACHE PATH "SCCameraFix gamedata catalog directory")
if(SCCAMERAFIX_SYNC_GAMEDATA)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_custom_target(SCCameraFixGameData
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/sync-gamedata.py"
            --manifest "${CMAKE_CURRENT_SOURCE_DIR}/scripts/manifests/sccamerafix.json"
            --target-dir "${SCCAMERAFIX_GAMEDATA_DIR}" --temp-root "${PROJECT_BINARY_DIR}/gamedata-sync"
        COMMENT "Synchronizing and validating SCCameraFix gamedata"
        VERBATIM
    )
    add_custom_target(SCCameraFixGameDataValidate
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/validate-gamedata.py"
            "${SCCAMERAFIX_GAMEDATA_DIR}" --manifest "${CMAKE_CURRENT_SOURCE_DIR}/scripts/manifests/sccamerafix.json"
        COMMENT "Validating SCCameraFix gamedata against the manifest"
        VERBATIM
    )
    add_dependencies(SCCameraFixGameDataValidate SCCameraFixGameData)
    add_dependencies(SCCameraFix SCCameraFixGameDataValidate)
endif()
install(DIRECTORY "${SCCAMERAFIX_GAMEDATA_DIR}/" DESTINATION svencoop/metahook/gamedata/sccamerafix OPTIONAL)

# The aggregate solution owns its single LaunchGame target.
if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
    option(METAHOOKSV_ENABLE_LAUNCH_GAME "Add the Visual Studio build/deploy/debug target" OFF)
    if(METAHOOKSV_ENABLE_LAUNCH_GAME)
        include(cmake/LaunchGame.cmake)
        metahooksv_add_launch_game()
    endif()
endif()
