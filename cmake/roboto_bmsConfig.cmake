# RobotoBmsConfig.cmake
#
# Config file for RobotoBms
#
# Defines the IMPORTED target: roboto_bms::roboto_bms

# Check if we already have the target
if(TARGET roboto_bms::roboto_bms)
    return()
endif()

# Compute the installation prefix relative to this file
get_filename_component(CURRENT_DIR "${CMAKE_CURRENT_LIST_FILE}" PATH)
# We install to ${PREFIX}/lib/cmake/RobotoBms/, so we go up 3 levels to get PREFIX
get_filename_component(_INSTALL_PREFIX "${CURRENT_DIR}/../../../" ABSOLUTE)

set(RobotoBms_INCLUDE_DIR "${_INSTALL_PREFIX}/include")
set(RobotoBms_LIB_DIR     "${_INSTALL_PREFIX}/lib")

# Find dependencies
include(CMakeFindDependencyMacro)
find_dependency(fmt)
find_dependency(spdlog)
find_dependency(Python3)
find_dependency(pybind11)

# Helper function to find and add libraries
function(_add_imported_lib _lib_name)
    find_library(LIB_${_lib_name} 
        NAMES ${_lib_name}
        PATHS ${RobotoBms_LIB_DIR}
        NO_DEFAULT_PATH
    )
    if(LIB_${_lib_name})
        list(APPEND RobotoBms_LIBRARIES ${LIB_${_lib_name}})
        set(RobotoBms_LIBRARIES ${RobotoBms_LIBRARIES} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not find roboto_bms library: ${_lib_name} in ${RobotoBms_LIB_DIR}")
    endif()
endfunction()

# Find all component libraries
set(RobotoBms_LIBRARIES "")
_add_imported_lib(bms)
_add_imported_lib(tws_bms)

# Create the INTERFACE target
add_library(roboto_bms::roboto_bms INTERFACE IMPORTED)

target_include_directories(roboto_bms::roboto_bms INTERFACE ${RobotoBms_INCLUDE_DIR})
target_link_libraries(roboto_bms::roboto_bms INTERFACE 
    ${RobotoBms_LIBRARIES}
    fmt::fmt
    spdlog::spdlog
)

message(STATUS "Found RobotoBms: ${_INSTALL_PREFIX}")
