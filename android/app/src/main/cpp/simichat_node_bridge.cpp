#include <jni.h>

#include <atomic>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include <android/log.h>
#include <unistd.h>

// The Android libnode.so shipped by nodejs-mobile exports this public Node
// embedding entry point. Keeping the declaration local avoids copying the
// complete Node/V8 header tree into the Flutter application source.
namespace node {
int Start(int argc, char* argv[]);
}

namespace {
constexpr char kLogTag[] = "SimiChatNodeRuntime";
std::atomic<bool> g_started{false};
std::atomic<bool> g_running{false};
std::thread g_node_thread;

std::string jstring_to_string(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) return {};
  std::string result(chars);
  env->ReleaseStringUTFChars(value, chars);
  return result;
}

std::vector<std::string> jobject_array_to_strings(JNIEnv* env,
                                                  jobjectArray values) {
  std::vector<std::string> result;
  if (values == nullptr) return result;
  const jsize length = env->GetArrayLength(values);
  result.reserve(static_cast<size_t>(length));
  for (jsize index = 0; index < length; ++index) {
    auto value = static_cast<jstring>(env->GetObjectArrayElement(values, index));
    result.push_back(jstring_to_string(env, value));
    env->DeleteLocalRef(value);
  }
  return result;
}
}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_top_simitalk_aichat_SimiChatNodeRuntime_nativeIsRunning(JNIEnv*, jobject) {
  return g_running.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_top_simitalk_aichat_SimiChatNodeRuntime_nativeStart(
    JNIEnv* env,
    jobject,
    jobjectArray arguments,
    jstring working_directory,
    jstring cache_directory) {
  bool expected = false;
  if (!g_started.compare_exchange_strong(expected, true)) {
    return g_running.load() ? JNI_TRUE : JNI_FALSE;
  }

  const std::string cwd = jstring_to_string(env, working_directory);
  const std::string cache = jstring_to_string(env, cache_directory);
  if (!cwd.empty() && chdir(cwd.c_str()) != 0) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                         "chdir failed for embedded Node: %s", cwd.c_str());
  }

  setenv("HOME", cwd.c_str(), 1);
  setenv("TMPDIR", cache.c_str(), 1);
  setenv("NODE_PATH", cwd.c_str(), 1);
  setenv("MCP_RUNTIME_HOST", "127.0.0.1", 1);
  setenv("SIMICHAT_NODE_RUNTIME_KIND", "android-embedded", 1);
  setenv("SIMICHAT_NODE_APP_MANAGED", "true", 1);

  auto argument_strings = jobject_array_to_strings(env, arguments);
  if (argument_strings.empty()) {
    argument_strings.emplace_back("node");
  }

  // Node/libuv keeps argv pointers while the runtime is alive. The vector of
  // strings and the pointer vector are owned by the Node thread until Start()
  // returns, so no JNI string memory can become invalid underneath Node.
  g_node_thread = std::thread([args = std::move(argument_strings)]() mutable {
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (auto& argument : args) {
      argv.push_back(argument.data());
    }
    argv.push_back(nullptr);

    g_running.store(true);
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                         "embedded Node starting (%s)",
                         args.size() > 1 ? args[1].c_str() : "no script");
    const int exit_code = node::Start(static_cast<int>(args.size()), argv.data());
    g_running.store(false);
    g_started.store(false);
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                         "embedded Node stopped with exit code %d", exit_code);
  });
  g_node_thread.detach();
  return JNI_TRUE;
}
