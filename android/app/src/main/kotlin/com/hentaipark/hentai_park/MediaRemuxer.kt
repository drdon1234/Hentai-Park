package com.hentaipark.hentai_park

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.DiscardingTrackOutput
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.ElementaryStreamReader
import androidx.media3.extractor.ts.H264Reader
import androidx.media3.extractor.ts.PesReader
import androidx.media3.extractor.ts.SeiReader
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.extractor.ts.TsPayloadReader
import androidx.media3.muxer.BufferInfo
import androidx.media3.muxer.Mp4Muxer
import androidx.media3.muxer.SeekableMuxerOutput
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.EOFException
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.util.concurrent.CancellationException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Local, streaming TS -> MP4 conversion. The caller owns the final rename of the temporary MP4. */
class MediaRemuxer(context: Context, messenger: BinaryMessenger) {
    private val roots = buildList {
        add(context.dataDir)
        add(context.cacheDir)
        addAll(context.getExternalFilesDirs(null).filterNotNull())
        addAll(context.externalCacheDirs.filterNotNull())
    }.map { it.canonicalFile }.distinct()
    private val main = Handler(Looper.getMainLooper())
    private val worker = object : ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        LinkedBlockingQueue<Runnable>(), ThreadFactory { runnable -> Thread(runnable, "park-media-remux") }) {
        override fun afterExecute(task: Runnable, error: Throwable?) {
            super.afterExecute(task, error)
            val remux = task as RemuxTask
            finish(remux.job, remux.failure ?: error)
        }
    }
    private val lock = Any()
    private val jobs = mutableMapOf<String, Job>()
    private var stopped = false
    private val channel = MethodChannel(messenger, "hentai_park/media").also {
        it.setMethodCallHandler(::handle)
    }

    private class Job(val id: String, val input: File, val output: File, val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
        val cancellations = mutableListOf<MethodChannel.Result>()
        var ownsOutput = false
        fun checkCancelled() {
            if (cancelled.get()) throw CancellationException("Media conversion cancelled")
        }
    }

    private inner class RemuxTask(val job: Job) : Runnable {
        var failure: Throwable? = null
        override fun run() { failure = run(job) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "remux" -> {
                    val id = argument(call, "id")
                    val input = localFile(argument(call, "input"))
                    val output = localFile(argument(call, "output"))
                    require(input != output) { "Input and output must differ" }
                    require(input.isFile && input.length() > 0) { "Missing TS input" }
                    require(!output.exists() && output.parentFile?.isDirectory == true) { "Output must be a new temporary file" }
                    val job = Job(id, input, output, result)
                    synchronized(lock) {
                        check(!stopped) { "Media service stopped" }
                        require(!jobs.containsKey(id)) { "Duplicate media job id" }
                        require(jobs.values.none { it.output == output || it.input == output || it.output == input }) { "Media file already in use" }
                        jobs[id] = job
                        worker.execute(RemuxTask(job))
                    }
                }
                "cancel" -> {
                    val id = argument(call, "id")
                    synchronized(lock) {
                        val job = jobs[id]
                        if (job == null) result.success(null)
                        else {
                            job.cancelled.set(true)
                            // Returned only after the worker has released files and removed its output.
                            job.cancellations.add(result)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("REMUX_ARGUMENT", error.message, null)
        }
    }

    private fun argument(call: MethodCall, name: String): String =
        (call.argument<Any>(name) as? String)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Missing $name")

    private fun localFile(path: String): File {
        require(File(path).isAbsolute) { "Expected absolute local path" }
        val file = File(path).canonicalFile
        require(roots.any { file.path.startsWith(it.path + File.separator) }) { "File is outside app data/cache" }
        return file
    }

    /** Does not block the UI. Queued jobs still run their cancellation cleanup before the executor exits. */
    fun shutdown() {
        channel.setMethodCallHandler(null)
        synchronized(lock) {
            stopped = true
            jobs.values.forEach { it.cancelled.set(true) }
            worker.shutdown()
        }
    }

    private fun run(job: Job): Throwable? {
        return try {
            job.checkCancelled()
            check(localFile(job.input.path) == job.input && localFile(job.output.path) == job.output) { "Media path changed" }
            // Never truncate or remove a pre-existing caller-owned file.
            check(job.output.createNewFile()) { "Temporary output already exists" }
            job.ownsOutput = true
            remux(job)
            null
        } catch (error: Throwable) {
            error
        }
    }

    // Called by afterExecute: the conversion Runnable has already exited and closed its files.
    private fun finish(job: Job, failure: Throwable?) {
        synchronized(lock) {
            var error = if (job.cancelled.get()) CancellationException("Media conversion cancelled") else failure
            var cleanupFailed = false
            if (error != null && job.ownsOutput) {
                try {
                    check(job.output.delete() || !job.output.exists()) { "Unable to remove incomplete MP4" }
                } catch (cleanupError: Exception) {
                    error.addSuppressed(cleanupError)
                    cleanupFailed = true
                }
            }
            jobs.remove(job.id)
            val finalError = error
            val cancellations = job.cancellations.toList()
            main.post {
                if (finalError == null) job.result.success(null)
                else job.result.error(if (finalError is CancellationException) "REMUX_CANCELLED" else "REMUX", finalError.message, null)
                cancellations.forEach {
                    if (cleanupFailed) it.error("REMUX_CLEANUP", finalError?.message, null)
                    else it.success(null)
                }
            }
        }
    }

    private class Track(val type: Int) {
        var format: Format? = null
        var samples = 0L
        var earliest = Long.MAX_VALUE
        var lastAudioTime = C.TIME_UNSET
        fun sample(time: Long) {
            check(format != null && time != C.TIME_UNSET) { "Missing sample format/timestamp" }
            if (type == C.TRACK_TYPE_AUDIO) {
                check(lastAudioTime == C.TIME_UNSET || time > lastAudioTime) { "Audio timestamps went backwards" }
                lastAudioTime = time
            }
            earliest = minOf(earliest, time)
            samples++
        }
    }

    // Metadata can point behind the buffer end. Retain only the sample and extractor look-ahead.
    private class SampleOutput(
        private val job: Job,
        private val track: Track,
        private val consume: (Long, Int, ByteArray, Int, Int) -> Unit,
    ) : TrackOutput {
        private var buffer = ByteArray(256 * 1024)
        private var used = 0
        override fun format(format: Format) {
            job.checkCancelled()
            check((track.type == C.TRACK_TYPE_VIDEO && format.sampleMimeType == MimeTypes.VIDEO_H264) ||
                (track.type == C.TRACK_TYPE_AUDIO && format.sampleMimeType == MimeTypes.AUDIO_AAC)) { "Unsupported TS codec" }
            val previous = track.format
            check(previous == null || (previous.sampleMimeType == format.sampleMimeType &&
                previous.initializationDataEquals(format) && previous.width == format.width &&
                previous.height == format.height && previous.sampleRate == format.sampleRate &&
                previous.channelCount == format.channelCount)) { "Media format changed inside TS" }
            track.format = format
        }
        private fun reserve(length: Int) {
            job.checkCancelled()
            check(length >= 0 && length <= 8 * 1024 * 1024 - used) { "Oversized media sample" }
            if (used + length > buffer.size) buffer = buffer.copyOf(maxOf(buffer.size * 2, used + length))
        }
        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
            check(sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN) { "Unsupported sample data" }
            reserve(length)
            data.readBytes(buffer, used, length)
            used += length
        }
        override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int): Int {
            check(sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN) { "Unsupported sample data" }
            reserve(length)
            val read = input.read(buffer, used, length)
            if (read == -1) {
                if (allowEndOfInput) return -1
                throw EOFException()
            }
            used += read
            return read
        }
        override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
            job.checkCancelled()
            check(cryptoData == null && flags and C.BUFFER_FLAG_ENCRYPTED == 0) { "Encrypted media unsupported" }
            check(size > 0 && offset >= 0 && offset <= used && size <= used - offset) { "Incomplete extracted sample" }
            track.sample(timeUs)
            consume(timeUs, flags, buffer, used - offset - size, size)
            buffer.copyInto(buffer, 0, used - offset, used)
            used = offset
        }
    }

    private fun extract(job: Job, output: ExtractorOutput) {
        val videoReaders = mutableListOf<EndAwareReader>()
        val defaults = DefaultTsPayloadReaderFactory()
        val factory = object : TsPayloadReader.Factory by defaults {
            override fun createPayloadReader(streamType: Int, esInfo: TsPayloadReader.EsInfo): TsPayloadReader? {
                if (streamType != TsExtractor.TS_STREAM_TYPE_H264) return defaults.createPayloadReader(streamType, esInfo)
                val reader = EndAwareReader(H264Reader(SeiReader(emptyList(), MimeTypes.VIDEO_MP2T), false, false, MimeTypes.VIDEO_MP2T))
                videoReaders.add(reader)
                return PesReader(reader)
            }
        }
        val extractor = TsExtractor(TsExtractor.MODE_HLS, TimestampAdjuster(TimestampAdjuster.MODE_NO_OFFSET), factory)
        try {
            FileInputStream(job.input).use { stream ->
                val input = DefaultExtractorInput(DataReader { bytes, offset, length ->
                    job.checkCancelled()
                    stream.read(bytes, offset, length)
                }, 0, job.input.length())
                job.checkCancelled()
                check(extractor.sniff(input)) { "Not a MPEG-TS stream" }
                input.resetPeekPosition()
                extractor.init(output)
                val position = PositionHolder()
                while (true) {
                    job.checkCancelled()
                    when (extractor.read(input, position)) {
                        Extractor.RESULT_END_OF_INPUT -> break
                        Extractor.RESULT_SEEK -> error("Unexpected seek in HLS TS")
                    }
                }
                job.checkCancelled()
                // Only the EOF of the entire concatenated TS may flush H.264's final sample.
                videoReaders.forEach { job.checkCancelled(); it.finishInput() }
            }
        } finally {
            extractor.release()
        }
    }

    private class EndAwareReader(private val delegate: ElementaryStreamReader) : ElementaryStreamReader by delegate {
        private var finished = false
        override fun consume(data: ParsableByteArray) {
            finished = false
            delegate.consume(data)
        }
        override fun packetFinished(isEndOfInput: Boolean) {
            if (isEndOfInput && finished) return
            delegate.packetFinished(isEndOfInput)
            if (isEndOfInput) finished = true
        }
        fun finishInput() {
            if (!finished) packetFinished(true)
        }
    }

    private fun remux(job: Job) {
        val tracks = linkedMapOf<Int, Track>()
        extract(job, object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput {
                if (type != C.TRACK_TYPE_AUDIO && type != C.TRACK_TYPE_VIDEO) return DiscardingTrackOutput()
                val track = tracks.getOrPut(id) { Track(type) }
                check(track.type == type) { "Track type changed" }
                return SampleOutput(job, track) { _, _, _, _, _ -> }
            }
            override fun endTracks() {}
            override fun seekMap(seekMap: SeekMap) {}
        })
        check(tracks.values.count { it.type == C.TRACK_TYPE_VIDEO } == 1 &&
            tracks.values.count { it.type == C.TRACK_TYPE_AUDIO } == 1 &&
            tracks.values.all { it.format != null && it.samples > 0 }) { "Missing or ambiguous audio/video tracks" }
        val base = tracks.values.minOf { it.earliest }
        job.checkCancelled()
        // Mp4Muxer.close() may throw a runtime metadata error before closing its output.
        // Own the output separately; use also preserves the original error if closing fails.
        SeekableMuxerOutput.of(job.output.path).use { muxerOutput ->
            Mp4Muxer.Builder(muxerOutput).setSampleCopyingEnabled(true).build().use { writer ->
                val destinations = tracks.mapValues { writer.addTrack(it.value.format!!) }
                val written = linkedMapOf<Int, Track>()
                extract(job, object : ExtractorOutput {
                    override fun track(id: Int, type: Int): TrackOutput {
                        if (type != C.TRACK_TYPE_AUDIO && type != C.TRACK_TYPE_VIDEO) return DiscardingTrackOutput()
                        val source = tracks[id] ?: error("Tracks changed between passes")
                        check(source.type == type) { "Track type changed between passes" }
                        val actual = written.getOrPut(id) { Track(type).also { it.format = source.format } }
                        val destination = destinations.getValue(id)
                        return SampleOutput(job, actual) { timeUs, flags, bytes, offset, size ->
                            job.checkCancelled()
                            check(timeUs >= base) { "Timestamp changed between passes" }
                            writer.writeSampleData(destination, ByteBuffer.wrap(bytes, offset, size).slice(),
                                BufferInfo(Math.subtractExact(timeUs, base), size, flags and C.BUFFER_FLAG_KEY_FRAME))
                        }
                    }
                    override fun endTracks() {}
                    override fun seekMap(seekMap: SeekMap) {}
                })
                check(written.keys == tracks.keys && written.all { (id, track) ->
                    track.samples == tracks.getValue(id).samples && track.earliest == tracks.getValue(id).earliest
                }) { "Samples changed between passes" }
                job.checkCancelled()
            }
        }
        job.checkCancelled()
        check(job.output.length() > 0) { "Empty MP4 output" }
    }
}
