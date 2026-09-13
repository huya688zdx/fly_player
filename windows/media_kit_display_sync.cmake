# 只修正固定版本的渲染入口，生成文件放在构建目录，保持 Pub 缓存原样。
get_target_property(_video_dir media_kit_video_plugin SOURCE_DIR)
file(READ "${_video_dir}/../pubspec.yaml" _video_pubspec)
if(NOT _video_pubspec MATCHES "\nversion: 2\\.0\\.1\n")
  message(FATAL_ERROR "显示同步修正仅适用于 media_kit_video 2.0.1，请审查升级后的渲染入口。")
endif()
file(READ "${_video_dir}/video_output.cc" _video_source)
# 以下替换针对已审查的 2.0.1 原文件，内容变化时必须重新确认锁和注销回调。
file(SHA256 "${_video_dir}/video_output.cc" _video_source_hash)
if(NOT _video_source_hash STREQUAL "198cb59a97070b61df5ee8ae35ac3e0bc344f3174f6e4aaf7b77e7357d606548")
  message(FATAL_ERROR "media_kit_video 源文件与已审查版本不同，无法应用纹理生命周期修正。")
endif()
set(_video_entry "void VideoOutput::Render() {\n  if (texture_id_) {")
string(FIND "${_video_source}" "${_video_entry}" _video_entry_offset)
if(_video_entry_offset LESS 0)
  message(FATAL_ERROR "media_kit_video 的 Render 入口已变化，无法应用显示同步修正。")
endif()
string(REPLACE "${_video_entry}" [=[void VideoOutput::Render() {
  if (texture_id_) {
    // libmpv 允许在 render 前等待垂直同步；重绘和音频同步帧不等待。
    static thread_local FlyMpvDisplaySync display_sync;
    display_sync.WaitForFrame(render_context_, handle_,
                             registrar_->GetView()->GetNativeWindow());]=]
  _video_source "${_video_source}")

# 只替换 Resize 的同步边界；先等 raster 注销旧纹理，再整体发布新 ID 和描述符。
string(FIND "${_video_source}" "void VideoOutput::Resize(" _resize_start)
string(FIND "${_video_source}" "int64_t VideoOutput::GetVideoWidth()" _resize_end)
math(EXPR _resize_length "${_resize_end} - ${_resize_start}")
string(SUBSTRING "${_video_source}" ${_resize_start} ${_resize_length} _resize_original)
set(_resize_source "${_resize_original}")
string(REPLACE "\n  if (texture_id_) {\n"
  "\n  if (texture_id_) {\n    auto released = std::make_shared<std::promise<void>>();\n    auto completion = released->get_future();\n"
  _resize_source "${_resize_source}")
string(REPLACE "texture_id_, [&, id = texture_id_]() {"
  "texture_id_, [&, id = texture_id_, released]() {"
  _resize_source "${_resize_source}")
string(REPLACE "            if (destroyed_) {\n              return;"
  "            if (destroyed_) {\n              released->set_value();\n              return;"
  _resize_source "${_resize_source}")
string(REPLACE "        });\n    texture_id_ = 0;\n  }" [=[          released->set_value();
        });
    // 不持纹理锁等待，允许正在执行的 raster 读取及注销回调完成。
    completion.wait();
  }
  std::lock_guard<std::mutex> lock(textures_mutex_);
  texture_id_ = 0;
  if (destroyed_) {
    return;
  }]=] _resize_source "${_resize_source}")
string(REPLACE "    std::lock_guard<std::mutex> lock(textures_mutex_);\n    textures_.emplace"
  "    textures_.emplace" _resize_source "${_resize_source}")
string(REPLACE "    std::lock_guard<std::mutex> lock(textures_mutex_);\n    pixel_buffer_textures_.emplace"
  "    pixel_buffer_textures_.emplace" _resize_source "${_resize_source}")
string(REPLACE "${_resize_original}" "${_resize_source}" _video_source "${_video_source}")

set(_video_source "#include \"mpv_display_sync.h\"\n${_video_source}")
set(_video_generated "${CMAKE_CURRENT_BINARY_DIR}/media_kit_display_sync/video_output.cc")
file(WRITE "${_video_generated}" "${_video_source}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${_video_dir}/video_output.cc" "${_video_dir}/../pubspec.yaml")

get_target_property(_video_sources media_kit_video_plugin SOURCES)
list(FIND _video_sources "video_output.cc" _video_source_index)
if(_video_source_index LESS 0)
  message(FATAL_ERROR "media_kit_video 的编译源列表已变化，无法应用显示同步修正。")
endif()
set(_video_patched_sources)
foreach(_video_file IN LISTS _video_sources)
  if(_video_file STREQUAL "video_output.cc")
    list(APPEND _video_patched_sources "${_video_generated}")
  else()
    get_filename_component(_video_absolute "${_video_file}" ABSOLUTE BASE_DIR "${_video_dir}")
    list(APPEND _video_patched_sources "${_video_absolute}")
  endif()
endforeach()
set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${_video_patched_sources}")
target_include_directories(media_kit_video_plugin PRIVATE "${_video_dir}" "${CMAKE_CURRENT_SOURCE_DIR}/runner")
target_compile_options(media_kit_video_plugin PRIVATE "/utf-8")
target_link_libraries(media_kit_video_plugin PRIVATE "dxgi.lib")
