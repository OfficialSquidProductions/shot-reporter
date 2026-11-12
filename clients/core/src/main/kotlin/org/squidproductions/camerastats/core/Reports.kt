package org.squidproductions.camerastats.core

object Reports {
    fun csv(report:Report):String {
        val keys=(Schema.take+Schema.settings).map { it.id }+listOf("flags","reviewed","entryID")
        fun quote(value:String)="\""+value.replace("\"","\"\"")+"\""
        return (listOf(keys.map(::quote).joinToString(","))+report.active.map { e -> keys.map { key -> quote(when(key) { "flags" -> e.flags.sorted().joinToString("; ");"reviewed" -> e.reviewed.toString();"entryID" -> e.id;else -> e.values[key].orEmpty() }) }.joinToString(",") }).joinToString("\r\n")+"\r\n"
    }
    fun html(report:Report):String {
        fun escape(v:String)=v.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;")
        val fields=Schema.take+Schema.settings
        val rows=report.active.joinToString("") { e -> "<tr>"+fields.joinToString("") { "<td>${escape(e.values[it.id].orEmpty())}</td>" }+"<td>${escape(e.flags.sorted().joinToString(", "))}</td></tr>" }
        return "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Shot Reporter report</title><style>body{font:14px system-ui;margin:32px;color:#241d21}table{border-collapse:collapse}td,th{border:1px solid #777;padding:8px;white-space:pre-wrap}thead{display:table-header-group}</style><h1>${escape(report.values["title"] ?: "Untitled")}</h1><p>A Squid Productions Software · Revision ${report.revision} · ${if(report.missing.isEmpty()) "Ready for Submission" else "DRAFT — ${report.missing.size} missing requirements"}</p><p>${escape(report.visibleProjectValues.toSortedMap().entries.joinToString(" · ") { "${it.key}: ${it.value}" })}</p><table><thead><tr>"+fields.joinToString("") { "<th>${escape(it.title)}</th>" }+"<th>Flags</th></tr></thead><tbody>$rows</tbody></table></html>"
    }
    /** Lines retain every field; native PDF adapters wrap and paginate these without truncation. */
    fun printable(report:Report):List<String> = buildList {
        add("Shot Reporter · Camera Report");add("A Squid Productions Software")
        add("${report.values["title"] ?: "Untitled"} · ${report.values["date"].orEmpty()} · Revision ${report.revision}")
        add(if(report.missing.isEmpty()) "READY FOR SUBMISSION · self-reviewed local report" else "DRAFT · ${report.missing.size} outstanding requirements")
        report.projectFields.forEach { add("${it.title}: ${report.values[it.id] ?: "—"}") }
        report.active.forEach { entry ->
            add("");add("SCENE ${entry.values["scene"].orEmpty()} · TAKE ${entry.values["take"].orEmpty()} · CAMERA ${entry.values["camera"].orEmpty()}")
            add("Flags: ${entry.flags.sorted().joinToString(", ").ifBlank { "None" }} · ${if(entry.reviewed) "Reviewed" else "Review pending"}")
            (Schema.take+Schema.settings).forEach { add("${it.title}: ${entry.values[it.id] ?: "—"}") }
        }
    }
}
