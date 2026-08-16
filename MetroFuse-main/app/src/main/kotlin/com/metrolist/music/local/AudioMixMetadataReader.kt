/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.local

import android.content.Context
import android.net.Uri
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.Locale
import kotlin.math.min

data class AudioMixMetadata(
    val bpm: Float? = null,
    val keySignature: String? = null,
)

object AudioMixMetadataReader {
    fun read(
        context: Context,
        uri: String,
    ): AudioMixMetadata? =
        runCatching {
            val bytes = readTagBytes(context, Uri.parse(uri))
            if (bytes.isEmpty()) return@runCatching null

            val id3 = readId3(bytes)
            val flac = readFlacVorbis(bytes)
            val mp4 = readMp4(bytes)
            val text = readLooseText(bytes)

            AudioMixMetadata(
                bpm = id3.bpm ?: flac.bpm ?: mp4.bpm ?: text.bpm,
                keySignature = id3.keySignature ?: flac.keySignature ?: mp4.keySignature ?: text.keySignature,
            ).takeIf { it.bpm != null || it.keySignature != null }
        }.getOrNull()

    private fun readTagBytes(
        context: Context,
        uri: Uri,
    ): ByteArray {
        val resolver = context.contentResolver
        val head = resolver.openInputStream(uri)?.use { it.readLimited(MAX_TAG_BYTES) } ?: ByteArray(0)
        val tail =
            runCatching {
                resolver.openAssetFileDescriptor(uri, "r")?.use { asset ->
                    val length = asset.length
                    if (length > MAX_TAG_BYTES) {
                        asset.createInputStream().use { input ->
                            input.skipFully(length - MAX_TAG_BYTES)
                            input.readLimited(MAX_TAG_BYTES)
                        }
                    } else {
                        ByteArray(0)
                    }
                }
            }.getOrNull() ?: ByteArray(0)
        return if (tail.isNotEmpty()) head + tail else head
    }

    private fun InputStream.readLimited(maxBytes: Int): ByteArray {
        val buffer = ByteArray(maxBytes)
        var offset = 0
        while (offset < maxBytes) {
            val read = read(buffer, offset, maxBytes - offset)
            if (read <= 0) break
            offset += read
        }
        return buffer.copyOf(offset)
    }

    private fun InputStream.skipFully(bytes: Long) {
        var remaining = bytes
        val scratch = ByteArray(8192)
        while (remaining > 0) {
            val skipped = skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
            } else {
                val read = read(scratch, 0, min(scratch.size.toLong(), remaining).toInt())
                if (read <= 0) return
                remaining -= read
            }
        }
    }

    private fun readId3(bytes: ByteArray): AudioMixMetadata {
        if (bytes.size < 10 || bytes[0] != 'I'.code.toByte() || bytes[1] != 'D'.code.toByte() || bytes[2] != '3'.code.toByte()) {
            return AudioMixMetadata()
        }
        val version = bytes[3].toInt()
        val tagSize = synchsafeInt(bytes, 6).coerceAtMost(bytes.size - 10)
        var offset = 10
        var bpm: Float? = null
        var key: String? = null

        while (offset + 10 <= 10 + tagSize && offset + 10 <= bytes.size) {
            val frameId = bytes.copyOfRange(offset, offset + 4).toString(StandardCharsets.ISO_8859_1)
            if (frameId.any { it.code == 0 }) break
            val frameSize =
                if (version >= 4) {
                    synchsafeInt(bytes, offset + 4)
                } else {
                    ByteBuffer.wrap(bytes, offset + 4, 4).order(ByteOrder.BIG_ENDIAN).int
                }
            if (frameSize <= 0 || offset + 10 + frameSize > bytes.size) break
            val payload = bytes.copyOfRange(offset + 10, offset + 10 + frameSize)
            when (frameId) {
                "TBPM" -> bpm = decodeId3Text(payload).toBpm()
                "TKEY" -> key = decodeId3Text(payload).toKeySignature()
            }
            offset += 10 + frameSize
        }
        return AudioMixMetadata(bpm = bpm, keySignature = key)
    }

    private fun readFlacVorbis(bytes: ByteArray): AudioMixMetadata {
        if (bytes.size < 8 || bytes.copyOfRange(0, 4).toString(StandardCharsets.ISO_8859_1) != "fLaC") {
            return AudioMixMetadata()
        }
        var offset = 4
        while (offset + 4 <= bytes.size) {
            val header = bytes[offset].toInt() and 0xFF
            val type = header and 0x7F
            val length =
                ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
                    ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                    (bytes[offset + 3].toInt() and 0xFF)
            val payloadStart = offset + 4
            val payloadEnd = payloadStart + length
            if (payloadEnd > bytes.size) break
            if (type == 4) {
                return readVorbisComments(bytes.copyOfRange(payloadStart, payloadEnd))
            }
            offset = payloadEnd
            if ((header and 0x80) != 0) break
        }
        return AudioMixMetadata()
    }

    private fun readVorbisComments(payload: ByteArray): AudioMixMetadata {
        fun readLittleInt(offset: Int): Int =
            ByteBuffer.wrap(payload, offset, 4).order(ByteOrder.LITTLE_ENDIAN).int

        var offset = 0
        if (offset + 4 > payload.size) return AudioMixMetadata()
        val vendorLength = readLittleInt(offset)
        if (vendorLength < 0 || offset + 4 + vendorLength > payload.size) return AudioMixMetadata()
        offset += 4 + vendorLength
        if (offset + 4 > payload.size) return AudioMixMetadata()
        val count = readLittleInt(offset)
        offset += 4
        var bpm: Float? = null
        var key: String? = null
        repeat(count.coerceIn(0, 128)) {
            if (offset + 4 > payload.size) return@repeat
            val length = readLittleInt(offset)
            offset += 4
            if (length < 0 || offset + length > payload.size) return@repeat
            val comment = payload.copyOfRange(offset, offset + length).toString(StandardCharsets.UTF_8)
            offset += length
            val name = comment.substringBefore('=').uppercase(Locale.US)
            val value = comment.substringAfter('=', "")
            when (name) {
                "BPM", "TBPM", "TEMPO" -> bpm = value.toBpm()
                "INITIALKEY", "INITIAL_KEY", "KEY", "TKEY" -> key = value.toKeySignature()
            }
        }
        return AudioMixMetadata(bpm = bpm, keySignature = key)
    }

    private fun readMp4(bytes: ByteArray): AudioMixMetadata {
        val tmpoIndex = bytes.indexOfAscii("tmpo")
        val bpm =
            if (tmpoIndex >= 0) {
                val dataIndex = bytes.indexOfAscii("data", tmpoIndex)
                if (dataIndex >= 8 && dataIndex + 18 <= bytes.size) {
                    val payloadStart = dataIndex + 12
                    val numeric = ((bytes[payloadStart].toInt() and 0xFF) shl 8) or (bytes[payloadStart + 1].toInt() and 0xFF)
                    numeric.takeIf { it in 40..240 }?.toFloat()
                } else {
                    null
                }
            } else {
                null
            }
        return AudioMixMetadata(bpm = bpm)
    }

    private fun readLooseText(bytes: ByteArray): AudioMixMetadata {
        val text = bytes.toString(StandardCharsets.ISO_8859_1)
        val bpm =
            Regex("""(?i)(?:TBPM|BPM|TEMPO)[=\u0000: ]+([0-9]{2,3}(?:\.[0-9]+)?)""")
                .find(text)
                ?.groupValues
                ?.getOrNull(1)
                ?.toBpm()
        val key =
            Regex("""(?i)(?:INITIALKEY|INITIAL_KEY|TKEY|KEY)[=\u0000: ]+([A-G][#b]?\s*(?:m|min|maj)?|[0-9]{1,2}[AB])""")
                .find(text)
                ?.groupValues
                ?.getOrNull(1)
                ?.toKeySignature()
        return AudioMixMetadata(bpm = bpm, keySignature = key)
    }

    private fun decodeId3Text(payload: ByteArray): String {
        if (payload.isEmpty()) return ""
        val charset =
            when (payload[0].toInt()) {
                1 -> Charsets.UTF_16
                2 -> Charset.forName("UTF-16BE")
                3 -> Charsets.UTF_8
                else -> StandardCharsets.ISO_8859_1
            }
        return payload.copyOfRange(1, payload.size).toString(charset).trim('\u0000', ' ', '\t', '\n', '\r')
    }

    private fun String.toBpm(): Float? =
        trim()
            .replace(',', '.')
            .toFloatOrNull()
            ?.takeIf { it in 40f..240f }

    private fun String.toKeySignature(): String? =
        trim()
            .replace(Regex("""\s+"""), "")
            .takeIf { it.length in 1..8 }

    private fun synchsafeInt(
        bytes: ByteArray,
        offset: Int,
    ): Int =
        ((bytes[offset].toInt() and 0x7F) shl 21) or
            ((bytes[offset + 1].toInt() and 0x7F) shl 14) or
            ((bytes[offset + 2].toInt() and 0x7F) shl 7) or
            (bytes[offset + 3].toInt() and 0x7F)

    private fun ByteArray.indexOfAscii(
        value: String,
        startIndex: Int = 0,
    ): Int {
        val needle = value.toByteArray(StandardCharsets.ISO_8859_1)
        for (i in startIndex..(size - needle.size)) {
            var match = true
            for (j in needle.indices) {
                if (this[i + j] != needle[j]) {
                    match = false
                    break
                }
            }
            if (match) return i
        }
        return -1
    }

    private const val MAX_TAG_BYTES = 512 * 1024
}
