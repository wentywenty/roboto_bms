cmake_minimum_required(VERSION 3.10)
project(bms_daemon)

set(CMAKE_CXX_STANDARD 14)

include_directories(include)

add_executable(bms_daemon 
    src/main.cpp 
    src/protocol.cpp
)

install(TARGETS bms_daemon DESTINATION usr/bin)
