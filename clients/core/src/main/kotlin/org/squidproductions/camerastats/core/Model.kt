package org.squidproductions.camerastats.core

import kotlinx.serialization.Serializable
import java.util.UUID
import java.time.Instant

fun identity(): String = UUID.randomUUID().toString().uppercase()
fun timestamp(): Double = (Instant.now().toEpochMilli() / 1000.0) - 978307200.0
class ReportException(message: String) : IllegalArgumentException(message)

@Serializable data class Entry(
    val id: String = identity(), val values: Map<String,String>, val flags: List<String> = emptyList(),
    val reviewed: Boolean = false, val deleted: Boolean = false, val created: Double = timestamp()
)
@Serializable data class Change(val date: Double = timestamp(), val device: String, val summary: String)
@Serializable data class Report(
    val id: String = identity(), val revision: Long = 0,
    val values: Map<String,String> = mapOf("date" to Instant.now().toString().take(10)),
    val defaults: Map<String,String> = mapOf("camera" to "A", "roll" to "A001", "load" to identity(), "playbackRate" to "24000/1001", "sensorRate" to "24000/1001"),
    val profile: String = Schema.profiles.first(), val positions: List<String> = listOf("All Duties"),
    val entries: List<Entry> = emptyList(), val history: List<Change> = emptyList(),
    val importedPackages: List<String> = emptyList(),
    // Opaque schema-1 compatibility data. Retained on import/export, never interpreted.
    val namingTemplate: String = "{project}_SC{scene}_TK{take}_CAM-{camera}"
) {
    val active: List<Entry> get() = entries.filterNot { it.deleted }
    fun record(summary: String, device: String): Report {
        require(revision<Long.MAX_VALUE) { "Report revision exceeds the supported range; original preserved." }
        return copy(revision = revision + 1, history = history + Change(device=device, summary=summary))
    }
    fun next(scene: String, device: String): Report {
        require(scene.isNotBlank()) { "Enter a scene / setup first." }
        val camera = defaults["camera"].orEmpty()
        val maximum = (active.filter { it.values["scene"] == scene && it.values["camera"].orEmpty() == camera }.mapNotNull { it.values["take"]?.toLongOrNull() }.maxOrNull() ?: 0L)
        require(maximum<Long.MAX_VALUE) { "Take number exceeds the supported range. Enter a manual take label instead." }
        val next=maximum+1
        return copy(entries = entries + Entry(values = defaults + mapOf("scene" to scene, "take" to next.toString()))).record("Added scene $scene, take $next, camera $camera",device)
    }
    val missing: List<String> get() = buildList {
        val required = listOf("title","date","director","dp","dit") + if (profile == Schema.profiles.first()) listOf("cycle","professor") else emptyList()
        required.filter { values[it].isNullOrBlank() }.forEach { key -> add(Schema.project.first { it.id == key }.title) }
        if (active.isEmpty()) add("At least one take")
        active.forEachIndexed { index, entry ->
            (Schema.settings + Schema.take.take(2)).filter { entry.values[it.id].isNullOrBlank() }.forEach { add("Row ${index+1}: ${it.title}") }
            if (!entry.reviewed) add("Row ${index+1}: review")
        }
    }
}
