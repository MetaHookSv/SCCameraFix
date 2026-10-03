set(SCCAMERAFIX_DEPENDENCY_CACHE_DIR "${PROJECT_SOURCE_DIR}/thirdparty/cache" CACHE PATH "Downloaded dependency cache")
set(VC_LTL_Root "${SCCAMERAFIX_DEPENDENCY_CACHE_DIR}/VC-LTL-5.3.1" CACHE PATH "VC-LTL binary package root")
set(METAHOOK_SOURCE_PATH "$ENV{METAHOOK_SOURCE_PATH}" CACHE PATH "MetaHook source tree; empty fetches the pinned SDK")

# The plugin compiles part of the SDK and includes its public headers, so an
# external tree must provide both the sources and the interfaces it uses.
function(sccamerafix_validate_metahook_source source)
    foreach(required include/metahook.h include/HLSDK/common/interface.cpp
        include/HLSDK/common/cvardef.h include/Interface/IPlugins.h)
        if(NOT EXISTS "${source}/${required}" OR IS_DIRECTORY "${source}/${required}")
            message(FATAL_ERROR "METAHOOK_SOURCE_PATH is missing ${required}: ${source}")
        endif()
    endforeach()
endfunction()

function(sccamerafix_prepare_dependencies)
    # External trees are read-only inputs; validate explicit paths before downloading anything.
    if(METAHOOK_SOURCE_PATH)
        get_filename_component(metahook_source "${METAHOOK_SOURCE_PATH}" ABSOLUTE BASE_DIR "${PROJECT_SOURCE_DIR}")
    else()
        include(FetchContent)
        FetchContent_Declare(sccamerafix_metahook
            GIT_REPOSITORY https://github.com/MetaHookSv/MetaHook
            GIT_TAG 4d23b6fecd79dc949aabc2e145480cd1328d4a35
            GIT_SUBMODULES ""
            # This SDK directory has no CMakeLists.txt: populate without building the launcher.
            SOURCE_SUBDIR include
        )
        FetchContent_MakeAvailable(sccamerafix_metahook)
        set(metahook_source "${sccamerafix_metahook_SOURCE_DIR}")
    endif()
    sccamerafix_validate_metahook_source("${metahook_source}")
    set(METAHOOK_SOURCE_PATH "${metahook_source}" PARENT_SCOPE)
    message(STATUS "METAHOOK_SOURCE_PATH: ${metahook_source}")

    # SCCameraFix consumes no Capstone and no SourceSDK headers, so there is
    # nothing else to resolve beyond the SDK tree and VC-LTL.
    include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/VCLTL.cmake")
    sccamerafix_prepare_vcltl()
endfunction()
