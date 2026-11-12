package org.squidproductions.camerastats.core

data class Field(val id: String, val title: String, val group: String)
object Schema {
    val project = listOf(
        Field("title", "Production title", "Project / crew"),
        Field("date", "Shooting date", "Project / crew"),
        Field("day", "Shooting day", "Project / crew"),
        Field("director", "Director", "Project / crew"),
        Field("dp", "Director of photography", "Project / crew"),
        Field("dit", "DIT / data — use N/A if unassigned", "Project / crew"),
        Field("cycle", "Cycle Group #", "Student"),
        Field("professor", "Cohort Professor", "Student"),
        Field("season", "Season", "Project / crew"),
        Field("episode", "Episode", "Project / crew")
    )
    val settings = listOf(
        Field("camera", "Camera", "Camera / media"),
        Field("mag", "SSD / physical mag", "Camera / media"),
        Field("load", "Load ID", "Camera / media"),
        Field("resolution", "Resolution", "Recording settings"),
        Field("compression", "Compression", "Recording settings"),
        Field("aspect", "Aspect ratio", "Recording settings"),
        Field("playbackRate", "Project time base (e.g. 24000/1001)", "Recording settings"),
        Field("sensorRate", "Varispeed / sensor FPS", "Recording settings"),
        Field("shutter", "Shutter angle / speed", "Recording settings"),
        Field("iso", "ISO", "Recording settings"),
        Field("temperature", "Color temperature / tint", "Recording settings"),
        Field("filters", "Filters / internal & external ND", "Recording settings"),
        Field("look", "Log / gamut / look reference", "Recording settings"),
        Field("lens", "Lens / focal length", "Lens / measurements"),
        Field("stop", "T-stop", "Lens / measurements"),
        Field("height", "Camera height (include units)", "Lens / measurements"),
        Field("distance", "Focus / subject distance (include units)", "Lens / measurements")
    )
    val take = listOf(
        Field("scene", "Scene / setup", "Slate"),
        Field("take", "Take label", "Slate"),
        Field("remarks", "Camera remarks", "Notes"),
        Field("dpNotes", "DP intent / selects", "Notes"),
        Field("continuity", "Script / continuity notes", "Notes"),
        Field("editorNotes", "Editorial notes", "Notes"),
        Field("sound", "Sound roll / file", "Post references"),
        Field("originalFilename", "Original clip filename", "Post references"),
        Field("timecode", "Source timecode (manual)", "Post references")
    )
    val profiles = listOf("Student / Cinematic Arts Full Report", "Small Crew / Combined Duties", "Feature / Television Department", "Custom Production")
    val positions = listOf("All Duties", "2nd AC", "1st AC", "DP / operator", "DIT / data", "Script / continuity")
    val flags = listOf("Circle","MOS","Pickup","Tail slate","False roll","Technical issue")
}
