cmake_minimum_required(VERSION 3.21)
project(halfbrowser_cef LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Point to CEF SDK
set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../cef/cef_binary_156.0.15+gcf671c0+chromium-156.0.8078.80_macosarm64_minimal" CACHE PATH "CEF root")

# Include CEF cmake
list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)

# Add libcef_dll_wrapper
add_subdirectory("${CEF_ROOT}/libcef_dll" libcef_dll_wrapper)

# Source files
set(SOURCES
    src/main.mm
    src/simple_handler.mm
    src/simple_handler.h
    src/keychain_helper.mm
    src/keychain_helper.h
    src/theme.mm
    src/theme.h
    src/bookmarks.mm
    src/bookmarks.h
    src/history_store.mm
    src/history_store.h
    src/backup_service.mm
    src/backup_service.h
    src/settings_store.mm
    src/settings_store.h
    src/favicon_service.mm
    src/favicon_service.h
    src/site_permissions.mm
    src/site_permissions.h
    src/form_login.mm
    src/form_login.h
    src/settings_window.mm
    src/settings_window.h
    src/bookmark_editor.mm
    src/bookmark_editor.h
    src/home_window.mm
    src/home_window.h
    src/cef_view.mm
    src/cef_view.h
    src/json_util.mm
    src/json_util.h
    src/url_util.mm
    src/url_util.h
    src/localization.mm
    src/localization.h
    src/url_util_test.mm
)

# Create executable
add_executable(halfbrowser_cef MACOSX_BUNDLE ${SOURCES})

# Link CEF
target_link_libraries(halfbrowser_cef
    libcef_dll_wrapper
    "${CEF_ROOT}/Release/Chromium Embedded Framework.framework"
    "${CMAKE_CURRENT_SOURCE_DIR}/../core/target/release/libhalf_browser_core.a"
    "-framework Cocoa"
    "-framework Foundation"
    "-framework Security"
)

target_include_directories(halfbrowser_cef PRIVATE
    "${CEF_ROOT}"
    "${CEF_ROOT}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

# Copy framework to bundle
set_target_properties(halfbrowser_cef PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "@executable_path/../Frameworks"
)

# Post-build: copy CEF framework
add_custom_command(TARGET halfbrowser_cef POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CEF_ROOT}/Release/Chromium Embedded Framework.framework"
        "$<TARGET_BUNDLE_DIR:halfbrowser_cef>/Contents/Frameworks/Chromium Embedded Framework.framework"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CEF_ROOT}/Release/Chromium Embedded Framework.framework/Resources"
        "$<TARGET_BUNDLE_DIR:halfbrowser_cef>/Contents/Frameworks/Chromium Embedded Framework.framework/Resources"
)
