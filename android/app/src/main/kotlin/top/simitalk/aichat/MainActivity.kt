package top.simitalk.aichat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.webkit.CookieManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var nodeRuntime: SimiChatNodeRuntime
    private var recorder: MediaRecorder? = null
    private var audioPlayer: MediaPlayer? = null
    private var audioPlayerChannel: MethodChannel? = null
    private var deepLinkChannel: MethodChannel? = null
    private var pendingInitialDeepLink: String? = null
    private var audioFocusRequest: Any? = null
    private var audioManager: AudioManager? = null
    private var competingAudioFocusRequest: Any? = null
    private var competingAudioManager: AudioManager? = null
    private var audioPlayerPath: String? = null
    private var recordingFile: File? = null
    private var recordingStartedAtMs: Long = 0L
    private var pendingRecordPermissionResult: MethodChannel.Result? = null
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            -> stopAudioPlayback()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> audioPlayer?.setVolume(0.3f, 0.3f)
            AudioManager.AUDIOFOCUS_GAIN -> audioPlayer?.setVolume(1.0f, 1.0f)
        }
    }
    private val competingAudioFocusChangeListener = AudioManager.OnAudioFocusChangeListener {}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nodeRuntime = SimiChatNodeRuntime(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SimiChatNodeRuntime.CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(nodeRuntime.status())
                "start" -> {
                    try {
                        result.success(nodeRuntime.start())
                    } catch (error: Throwable) {
                        result.error("NODE_RUNTIME_START_FAILED", error.message, null)
                    }
                }
                "stop" -> result.success(nodeRuntime.stop())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DATA_EXPORT_SHARE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            shareExportFile(call.arguments as? Map<*, *>, result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IN_APP_H5_PROFILE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "flush") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                CookieManager.getInstance().flush()
                result.success(true)
            } catch (error: Throwable) {
                result.error("WEBVIEW_PROFILE_FLUSH_FAILED", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOICE_RECORDER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> startVoiceRecording(result)
                "stopRecording" -> stopVoiceRecording(result)
                "cancelRecording" -> cancelVoiceRecording(result)
                else -> result.notImplemented()
            }
        }
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        ).also { channel ->
            pendingInitialDeepLink = extractSimiDeepLink(intent)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(pendingInitialDeepLink)
                        pendingInitialDeepLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        audioPlayerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_PLAYER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "playFile" -> playAudioFile(call.arguments as? Map<*, *>, result)
                    "stop" -> {
                        stopAudioPlayback()
                        result.success(true)
                    }
                    "simulateAudioFocusLossForTesting" -> {
                        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                        audioFocusChangeListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
                        result.success(true)
                    }
                    "requestCompetingAudioFocusForTesting" -> {
                        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                        result.success(requestCompetingAudioFocusForTesting())
                    }
                    "abandonCompetingAudioFocusForTesting" -> {
                        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                        abandonCompetingAudioFocusForTesting()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractSimiDeepLink(intent) ?: return
        val channel = deepLinkChannel
        if (channel == null) {
            pendingInitialDeepLink = link
            return
        }
        runOnUiThread {
            channel.invokeMethod("linkOpened", link)
        }
    }

    private fun extractSimiDeepLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        if (data.scheme != "ai-chat") return null
        return data.toString()
    }

    private fun shareExportFile(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val path = arguments?.get("path") as? String
        val mimeType = arguments?.get("mimeType") as? String ?: "application/gzip"
        val subject = arguments?.get("subject") as? String ?: "SimiChat 数据导出包"
        val text = arguments?.get("text") as? String ?: "SimiChat 本地数据导出包。请只分享到可信目标。"
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "缺少导出文件路径", null)
            return
        }

        val file = File(path).canonicalFile
        if (!file.exists() || !file.isFile) {
            result.error("FILE_NOT_FOUND", "导出文件不存在", null)
            return
        }
        if (!isSimiChatExportArchive(file.name)) {
            result.error("INVALID_EXPORT_FILE", "只能分享 SimiChat 导出压缩包", null)
            return
        }
        val appDataDir = File(applicationInfo.dataDir).canonicalFile
        if (!file.path.startsWith(appDataDir.path + File.separator)) {
            result.error("OUTSIDE_APP_DATA", "导出文件必须位于应用私有目录", null)
            return
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(shareIntent, subject)
        startActivity(chooser)
        result.success(true)
    }

    private fun isSimiChatExportArchive(fileName: String): Boolean {
        return fileName.startsWith("simichat-export-") && fileName.endsWith(".tar.gz")
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        if (recorder != null) {
            result.error("ALREADY_RECORDING", "正在录音中", null)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            if (pendingRecordPermissionResult != null) {
                result.error("PERMISSION_REQUEST_ACTIVE", "麦克风权限请求正在进行中", null)
                return
            }
            pendingRecordPermissionResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_PERMISSION_REQUEST,
            )
            return
        }
        beginVoiceRecording(result)
    }

    private fun beginVoiceRecording(result: MethodChannel.Result) {
        val directory = File(cacheDir, "simichat_recordings")
        if (!directory.exists() && !directory.mkdirs()) {
            result.error("CREATE_FILE_FAILED", "无法创建录音目录", null)
            return
        }
        val file = File(directory, "simichat-recording-${System.currentTimeMillis()}.m4a")
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioEncodingBitRate(128000)
            mediaRecorder.setAudioSamplingRate(44100)
            mediaRecorder.setOutputFile(file.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()
            recorder = mediaRecorder
            recordingFile = file
            recordingStartedAtMs = System.currentTimeMillis()
            result.success(true)
        } catch (e: Exception) {
            try {
                mediaRecorder.release()
            } catch (_: Exception) {
            }
            file.delete()
            result.error("START_RECORDING_FAILED", "启动录音失败", null)
        }
    }

    private fun stopVoiceRecording(result: MethodChannel.Result) {
        val mediaRecorder = recorder
        val file = recordingFile
        if (mediaRecorder == null || file == null) {
            result.error("NOT_RECORDING", "当前没有正在进行的录音", null)
            return
        }
        recorder = null
        recordingFile = null
        val durationMs = (System.currentTimeMillis() - recordingStartedAtMs).coerceAtLeast(0L)
        try {
            mediaRecorder.stop()
        } catch (_: Exception) {
            try {
                mediaRecorder.release()
            } catch (_: Exception) {
            }
            file.delete()
            result.error("RECORDING_TOO_SHORT", "录音时间太短", null)
            return
        }
        try {
            mediaRecorder.release()
        } catch (_: Exception) {
        }
        if (!file.exists() || file.length() <= 0L) {
            file.delete()
            result.error("RECORDING_TOO_SHORT", "录音时间太短", null)
            return
        }
        result.success(
            mapOf(
                "path" to file.absolutePath,
                "fileName" to file.name,
                "mimeType" to "audio/mp4",
                "fileSize" to file.length(),
                "durationMs" to durationMs,
            ),
        )
    }

    private fun cancelVoiceRecording(result: MethodChannel.Result) {
        val mediaRecorder = recorder
        val file = recordingFile
        recorder = null
        recordingFile = null
        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop()
            } catch (_: Exception) {
            }
            try {
                mediaRecorder.release()
            } catch (_: Exception) {
            }
        }
        file?.delete()
        result.success(true)
    }

    private fun playAudioFile(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val path = arguments?.get("path") as? String
        // Direct integration tests do not run through the normal user-tap
        // foreground audio-focus flow. Product calls must not set this flag.
        val skipAudioFocusRequest = arguments?.get("skipAudioFocusRequest") == true
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "缺少语音文件路径", null)
            return
        }
        val file = try {
            File(path).canonicalFile
        } catch (_: Exception) {
            result.error("FILE_NOT_FOUND", "语音文件不存在", null)
            return
        }
        if (!file.exists() || !file.isFile) {
            result.error("FILE_NOT_FOUND", "语音文件不存在", null)
            return
        }
        if (!isInsideAppStorage(file)) {
            result.error("OUTSIDE_APP_DATA", "只能播放应用私有目录内的语音文件", null)
            return
        }

        stopAudioPlayback()
        val player = MediaPlayer()
        val audioPath = file.absolutePath
        try {
            player.setDataSource(audioPath)
            player.setOnCompletionListener {
                if (audioPlayer === it) {
                    audioPlayer = null
                    audioPlayerPath = null
                    abandonAudioPlaybackFocus()
                    emitAudioPlaybackEvent("playbackCompleted", audioPath)
                }
                try {
                    it.release()
                } catch (_: Exception) {
                }
            }
            player.setOnErrorListener { mp, _, _ ->
                if (audioPlayer === mp) {
                    audioPlayer = null
                    audioPlayerPath = null
                    abandonAudioPlaybackFocus()
                    emitAudioPlaybackEvent("playbackError", audioPath)
                }
                try {
                    mp.release()
                } catch (_: Exception) {
                }
                true
            }
            player.prepare()
            if (!skipAudioFocusRequest) {
                if (!requestAudioPlaybackFocus()) {
                    try {
                        player.release()
                    } catch (_: Exception) {
                    }
                    result.error("AUDIO_FOCUS_DENIED", "无法获取音频播放焦点", null)
                    return
                }
            }
            player.start()
            audioPlayer = player
            audioPlayerPath = audioPath
            result.success(true)
        } catch (_: Exception) {
            try {
                player.release()
            } catch (_: Exception) {
            }
            audioPlayer = null
            audioPlayerPath = null
            abandonAudioPlaybackFocus()
            result.error("PLAY_FAILED", "语音播放失败，请稍后重试", null)
        }
    }

    private fun stopAudioPlayback() {
        val player = audioPlayer ?: return
        val stoppedPath = audioPlayerPath
        audioPlayer = null
        audioPlayerPath = null
        abandonAudioPlaybackFocus()
        try {
            if (player.isPlaying) {
                player.stop()
            }
        } catch (_: Exception) {
        }
        try {
            player.release()
        } catch (_: Exception) {
        }
        emitAudioPlaybackEvent("playbackStopped", stoppedPath)
    }

    private fun requestAudioPlaybackFocus(): Boolean {
        val manager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        audioManager = manager
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()
            audioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            abandonAudioPlaybackFocus()
            return false
        }
        return true
    }

    private fun abandonAudioPlaybackFocus() {
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (audioFocusRequest as? AudioFocusRequest)?.let {
                manager.abandonAudioFocusRequest(it)
            }
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(audioFocusChangeListener)
        }
        audioFocusRequest = null
        audioManager = null
    }

    private fun requestCompetingAudioFocusForTesting(): Boolean {
        val manager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        competingAudioManager = manager
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setOnAudioFocusChangeListener(competingAudioFocusChangeListener)
                .build()
            competingAudioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                competingAudioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            abandonCompetingAudioFocusForTesting()
            return false
        }
        return true
    }

    private fun abandonCompetingAudioFocusForTesting() {
        val manager = competingAudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (competingAudioFocusRequest as? AudioFocusRequest)?.let {
                manager.abandonAudioFocusRequest(it)
            }
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(competingAudioFocusChangeListener)
        }
        competingAudioFocusRequest = null
        competingAudioManager = null
    }

    private fun emitAudioPlaybackEvent(method: String, path: String?) {
        runOnUiThread {
            audioPlayerChannel?.invokeMethod(method, mapOf("path" to path))
        }
    }

    private fun isInsideAppStorage(file: File): Boolean {
        val roots = listOf(
            File(applicationInfo.dataDir),
            filesDir,
            cacheDir,
        )
        return roots.any { root ->
            val canonicalRoot = root.canonicalFile
            file.path == canonicalRoot.path || file.path.startsWith(canonicalRoot.path + File.separator)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RECORD_AUDIO_PERMISSION_REQUEST) return
        val result = pendingRecordPermissionResult ?: return
        pendingRecordPermissionResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            beginVoiceRecording(result)
        } else {
            result.error("PERMISSION_DENIED", "麦克风权限被拒绝", null)
        }
    }

    override fun onDestroy() {
        stopAudioPlayback()
        abandonCompetingAudioFocusForTesting()
        super.onDestroy()
    }

    companion object {
        private const val DATA_EXPORT_SHARE_CHANNEL = "simichat/data_export_share"
        private const val VOICE_RECORDER_CHANNEL = "simichat/voice_recorder"
        private const val AUDIO_PLAYER_CHANNEL = "simichat/audio_player"
        private const val DEEP_LINK_CHANNEL = "simichat/deep_link"
        private const val IN_APP_H5_PROFILE_CHANNEL = "simichat/in_app_h5_profile"
        private const val RECORD_AUDIO_PERMISSION_REQUEST = 4107
    }
}
