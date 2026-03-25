cmake_minimum_required(VERSION 3.12)
project(roboto_bms)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")
if(NOT CMAKE_CROSSCOMPILING)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
endif()
set(CMAKE_CXX_COMPILER_LAUNCHER ccache)

set(THREADS_PREFER_PTHREAD_FLAG ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_BUILD_TYPE Release)

find_package(ament_cmake QUIET)
find_package(spdlog REQUIRED)
find_package(fmt REQUIRED)
find_package(Python3 COMPONENTS Interpreter Development REQUIRED)
find_package(pybind11 REQUIRED)

set(PUBLIC_DEPENDENCIES
    fmt::fmt spdlog::spdlog pthread)

add_subdirectory(src/drivers)

# ---- Daemon executable ----
add_executable(bms_daemon
    src/main.cpp
)
target_include_directories(bms_daemon PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(bms_daemon PRIVATE tws_bms_protocol pthread)

# ---- Client library ----
add_library(bms STATIC
    src/bms_driver.cpp
)
target_include_directories(bms
    PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(bms PUBLIC ${PUBLIC_DEPENDENCIES} tws_bms)

# ---- Python bindings ----
pybind11_add_module(bms_py src/pybind_module.cpp)
target_link_libraries(bms_py PUBLIC bms)

# ---- Install ----
install(DIRECTORY include/ DESTINATION include)

install(TARGETS bms_daemon DESTINATION bin)

install(TARGETS bms tws_bms
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

# Install our custom Config for non-ROS consumers (Deb mode)
install(FILES cmake/roboto_bmsConfig.cmake
  DESTINATION lib/cmake/roboto_bms
)

set(PYTHON_INSTALL_DIR "lib/python${Python3_VERSION_MAJOR}.${Python3_VERSION_MINOR}/site-packages")
install(TARGETS bms_py
    LIBRARY DESTINATION ${PYTHON_INSTALL_DIR}
    ARCHIVE DESTINATION ${PYTHON_INSTALL_DIR}
    RUNTIME DESTINATION ${PYTHON_INSTALL_DIR}
)

if(ament_cmake_FOUND)
  ament_export_libraries(bms tws_bms)
  ament_export_include_directories(include)
  ament_package()
endif()
