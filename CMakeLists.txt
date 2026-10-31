cmake_minimum_required(VERSION 3.20)
project(LabelPrint LANGUAGES NONE)

# CLion build entry points; SwiftPM and Cargo own compilation and dependencies.
add_custom_target(LabelPrint ALL
    COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/build.sh"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL)
add_custom_target(Check
    COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/test.sh"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL)
add_custom_target(PackageApp
    COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/package.sh"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL)
