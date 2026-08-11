package top.simitalk.aichat

import android.content.Context
import android.content.res.AssetManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Owns the Node.js runtime shipped inside the Android APK.
 *
 * This is deliberately a small platform boundary. The MCP server remains a
 * normal Node.js module/script, while libnode.so is started in a dedicated
 * native thread. No host node, npx, Docker, or network download is involved
 * after the APK is installed.
 */
class SimiChatNodeRuntime(private val context: Context) {
    companion object {
        const val CHANNEL = "top.simitalk.aichat/node_runtime"
        const val PORT = 37651
        private const val STATE_STOPPED = 0
        private const val STATE_STARTING = 1
        private const val STATE_RUNNING = 2
        private const val STATE_CRASHED = 3

    }

    private val prepared = AtomicBoolean(false)
    private val restartCount = AtomicInteger(0)
    @Volatile private var nativeLoaded = false
    @Volatile private var nativeLoadError: String? = null
    private val runtimeDirectory: File
        get() = File(context.filesDir, "simichat_node_runtime")
    private val scriptFile: File
        get() = File(runtimeDirectory, "runtime-server.mjs")

    fun start(): Map<String, Any> {
        if (!ensureNativeLoaded()) return info(false)
        prepareAssets()
        if (nativeState() == STATE_CRASHED) {
            restartCount.incrementAndGet()
        }
        val started = nativeStart(
            arrayOf("node", scriptFile.absolutePath),
            runtimeDirectory.absolutePath,
            context.cacheDir.absolutePath,
        )
        // `started` also covers the short STARTING window. Returning it as a
        // positive start acknowledgement lets Dart wait for /health instead
        // of reporting a transient false negative to the MCP layer.
        return info(started || nativeIsRunning())
    }

    fun status(): Map<String, Any> {
        if (!ensureNativeLoaded()) return info(false)
        return info(nativeIsRunning())
    }

    fun stop(): Map<String, Any> {
        // The embedded Node entry point is intentionally process-lifetime
        // scoped. Android destroys the app process and its Node loop together;
        // exposing a fake stop would make the UI report a false state.
        return status() + mapOf("stopSupported" to false)
    }

    private fun info(running: Boolean): Map<String, Any> {
        val loaded = nativeLoaded
        val currentNativeState = if (loaded) nativeState() else STATE_CRASHED
        val exitCode = if (loaded) nativeExitCode() else -1
        return mapOf(
            "running" to running,
            "state" to stateName(currentNativeState),
            "nativeState" to currentNativeState,
            "nativeExitCode" to exitCode,
            "restartCount" to restartCount.get(),
            "lastError" to if (currentNativeState == STATE_CRASHED) {
                nativeLoadError ?: "embedded Node exited with code $exitCode"
            } else {
                ""
            },
            "runtime" to "simichat-node-android-embedded",
            "dependencyMode" to "bundled_nodejs_mobile",
            "externalProcess" to false,
            "appManaged" to true,
            "requiresHostNode" to false,
            "requiresHostNpx" to false,
            "requiresDocker" to false,
            "nodeVersion" to "18.20.4-mobile",
            "abi" to android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
            "healthUrl" to "http://127.0.0.1:$PORT/health",
            "sseUrl" to "http://127.0.0.1:$PORT/mcp/sse/simichat-node",
            "scriptPath" to scriptFile.absolutePath,
        )
    }

    private fun ensureNativeLoaded(): Boolean {
        if (nativeLoaded) return true
        synchronized(this) {
            if (nativeLoaded) return true
            return try {
                // Load lazily so an unsupported ABI or a missing native
                // dependency cannot crash the chat UI before the first frame.
                System.loadLibrary("node")
                System.loadLibrary("simichat_node_bridge")
                nativeLoaded = true
                nativeLoadError = null
                true
            } catch (error: Throwable) {
                nativeLoadError = "embedded Node native library unavailable: ${error.message ?: error::class.java.simpleName}"
                false
            }
        }
    }

    private fun stateName(value: Int): String = when (value) {
        STATE_STARTING -> "starting"
        STATE_RUNNING -> "running"
        STATE_CRASHED -> "crashed"
        else -> "stopped"
    }

    private fun prepareAssets() {
        if (prepared.get()) return
        runtimeDirectory.mkdirs()
        copyAssetIfChanged("tools/mcp_runtime/container/runtime-server.mjs", scriptFile)
        prepared.set(true)
    }

    private fun copyAssetIfChanged(assetPath: String, target: File) {
        val marker = File(target.parentFile, ".${target.name}.sha256")
        val bytes = listOf("flutter_assets/$assetPath", assetPath)
            .asSequence()
            .mapNotNull { path ->
                try {
                    context.assets.open(path).use { it.readBytes() }
                } catch (_: java.io.IOException) {
                    null
                }
            }
            .firstOrNull()
            ?: error("Flutter asset not found: $assetPath")
        val digest = java.security.MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
        if (target.isFile && marker.isFile && marker.readText() == digest) return
        FileOutputStream(target).use { it.write(bytes) }
        marker.writeText(digest)
    }

    private external fun nativeIsRunning(): Boolean

    private external fun nativeState(): Int

    private external fun nativeExitCode(): Int

    private external fun nativeStart(
        arguments: Array<String>,
        workingDirectory: String,
        cacheDirectory: String,
    ): Boolean

}
