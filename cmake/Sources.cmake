# Explicit compile list from SCCameraFix.vcxproj. interface.cpp is provided by the
# MetaHook SDK because EXPOSE_SINGLE_INTERFACE, which exports CreateInterface, lives there.
set(SCCAMERAFIX_SOURCES
    "${PROJECT_SOURCE_DIR}/src/exportfuncs.cpp"
    "${PROJECT_SOURCE_DIR}/src/mathlib2.cpp"
    "${PROJECT_SOURCE_DIR}/src/plugins.cpp"
    "${PROJECT_SOURCE_DIR}/src/privatehook.cpp"
    "${METAHOOK_SOURCE_PATH}/include/HLSDK/common/interface.cpp"
)
