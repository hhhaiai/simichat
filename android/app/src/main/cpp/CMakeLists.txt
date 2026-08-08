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
# Android 16 KB devices require every newly linked ELF load segment to be
# aligned for a 16 KB page. This fixes the bridge; the prebuilt libnode.so is
# audited separately by scripts/verify_android_native_16k.sh and must also be
# rebuilt with the same flags before 16 KB support can be marked verified.
target_link_options(simichat_node_bridge PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,-z,common-page-size=16384"
)
target_link_libraries(simichat_node_bridge node ${log-lib} ${android-lib} ${cxx-shared})
