cmake_minimum_required(VERSION 3.22.1)

project(simichat_node_bridge)

add_library(simichat_node_bridge SHARED simichat_node_bridge.cpp)

add_library(node SHARED IMPORTED)
set_target_properties(node PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libnode.so"
)

find_library(log-lib log)
find_library(android-lib android)
find_library(cxx-shared c++_shared)

target_compile_features(simichat_node_bridge PRIVATE cxx_std_17)
target_link_libraries(simichat_node_bridge node ${log-lib} ${android-lib} ${cxx-shared})
