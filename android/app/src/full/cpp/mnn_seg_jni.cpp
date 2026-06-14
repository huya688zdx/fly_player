// MNN segmentation JNI bridge for danmaku dynamic occlusion.
//
// Replaces the FastDeploy/PaddleSeg backend. Wraps an MNN Interpreter+Session
// per model. Kotlin side does bitmap preprocessing and passes a normalized
// NCHW float buffer; this returns the foreground mask (N*N floats, input size).
//
// Built externally with the NDK against the prebuilt libMNN.so (see
// docs/danmaku-occlusion-rework-plan.md for the build command). The model is
// fully convolutional (ISNet/U2Net) so one handle can run at multiple input
// sizes via resizeTensor — call nativeRun with the desired N.
#include <jni.h>
#include <android/log.h>
#include <MNN/Interpreter.hpp>
#include <MNN/Tensor.hpp>
#include <MNN/MNNForwardType.h>
#include <memory>
#include <mutex>

#define LOG_TAG "FlyPlayerMnnSeg"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

struct SegHandle {
    std::shared_ptr<MNN::Interpreter> net;
    MNN::Session* session = nullptr;
    MNN::Tensor* input = nullptr;   // session input (device)
    MNN::Tensor* output = nullptr;  // session output (device)
    int currentN = 0;
    std::mutex lock;  // guards run() — one inference at a time per handle
};

// Map wire value to MNN forward type. 0=CPU 3=OpenCL 7=Vulkan.
MNNForwardType toForwardType(jint backend) {
    switch (backend) {
        case 3: return MNN_FORWARD_OPENCL;
        case 7: return MNN_FORWARD_VULKAN;
        default: return MNN_FORWARD_CPU;
    }
}

bool ensureResized(SegHandle* h, int n) {
    if (h->currentN == n && h->input != nullptr && h->output != nullptr) {
        return true;
    }
    h->net->resizeTensor(h->input, {1, 3, n, n});
    h->net->resizeSession(h->session);
    h->output = h->net->getSessionOutput(h->session, nullptr);
    h->currentN = n;
    return h->output != nullptr;
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_geqian_flyplayer_fly_1player_mpv_MnnSegNative_nativeCreate(
        JNIEnv* env, jclass, jstring modelPath, jint backend, jint threads) {
    const char* path = env->GetStringUTFChars(modelPath, nullptr);
    auto net = std::shared_ptr<MNN::Interpreter>(MNN::Interpreter::createFromFile(path));
    env->ReleaseStringUTFChars(modelPath, path);
    if (!net) {
        LOGE("createFromFile failed");
        return 0;
    }

    MNN::ScheduleConfig config;
    config.type = toForwardType(backend);
    config.numThread = threads > 0 ? threads : 4;
    MNN::BackendConfig bn;
    bn.precision = MNN::BackendConfig::Precision_Low;   // fp16 on GPU
    bn.power = MNN::BackendConfig::Power_High;
    config.backendConfig = &bn;

    MNN::Session* session = net->createSession(config);
    if (!session) {
        LOGE("createSession failed backend=%d", backend);
        return 0;
    }
    auto* h = new SegHandle();
    h->net = net;
    h->session = session;
    h->input = net->getSessionInput(session, nullptr);
    if (h->input == nullptr) {
        LOGE("no session input");
        net->releaseSession(session);
        delete h;
        return 0;
    }
    LOGI("MNN session created backend=%d threads=%d", backend, config.numThread);
    return reinterpret_cast<jlong>(h);
}

// input: normalized NCHW float buffer of length 3*n*n. Returns mask float[n*n]
// (foreground probability after sigmoid, model output is input-sized).
JNIEXPORT jfloatArray JNICALL
Java_com_geqian_flyplayer_fly_1player_mpv_MnnSegNative_nativeRun(
        JNIEnv* env, jclass, jlong handle, jfloatArray input, jint n) {
    auto* h = reinterpret_cast<SegHandle*>(handle);
    if (h == nullptr || n <= 0) {
        return nullptr;
    }
    std::lock_guard<std::mutex> guard(h->lock);
    if (!ensureResized(h, n)) {
        LOGE("resize failed n=%d", n);
        return nullptr;
    }

    const int inCount = 3 * n * n;
    if (env->GetArrayLength(input) < inCount) {
        LOGE("input too small: %d < %d", env->GetArrayLength(input), inCount);
        return nullptr;
    }

    // copy host -> device input
    MNN::Tensor hostIn(h->input, h->input->getDimensionType());
    jfloat* src = env->GetFloatArrayElements(input, nullptr);
    memcpy(hostIn.host<float>(), src, sizeof(float) * inCount);
    env->ReleaseFloatArrayElements(input, src, JNI_ABORT);
    h->input->copyFromHostTensor(&hostIn);

    h->net->runSession(h->session);

    MNN::Tensor hostOut(h->output, h->output->getDimensionType());
    h->output->copyToHostTensor(&hostOut);
    const int outCount = hostOut.elementSize();
    jfloatArray result = env->NewFloatArray(outCount);
    if (result == nullptr) {
        return nullptr;
    }
    env->SetFloatArrayRegion(result, 0, outCount, hostOut.host<float>());
    return result;
}

JNIEXPORT void JNICALL
Java_com_geqian_flyplayer_fly_1player_mpv_MnnSegNative_nativeDestroy(
        JNIEnv*, jclass, jlong handle) {
    auto* h = reinterpret_cast<SegHandle*>(handle);
    if (h == nullptr) {
        return;
    }
    if (h->net && h->session) {
        h->net->releaseSession(h->session);
    }
    delete h;
}

}  // extern "C"
