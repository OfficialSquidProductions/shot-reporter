package org.squidproductions.camerastats.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.*
import java.math.BigDecimal
import java.security.MessageDigest
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.nio.charset.CodingErrorAction

object Exchange {
    const val LIMIT = 32 * 1024 * 1024
    val json = Json { encodeDefaults=true; ignoreUnknownKeys=false; isLenient=false; allowSpecialFloatingPointValues=false }
    private val manifestJson = Json(json) { ignoreUnknownKeys=true }
    @Serializable data class Manifest(val format:String="org.squidproductions.camreport",val schema:Int=1,val packageID:String=identity(),val reportID:String,val revision:Long,val device:String,val scope:String="full-report",val sha256:String)
    data class Package(val manifest:Manifest,val report:Report)
    data class Preview(val additions:List<Entry>,val conflicts:List<String>,val duplicate:Boolean)
    fun digest(bytes:ByteArray):String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun sorted(element:JsonElement):JsonElement = when(element) {
        is JsonObject -> JsonObject(element.toSortedMap().mapValues { sorted(it.value) })
        is JsonArray -> JsonArray(element.map(::sorted))
        else -> element
    }
    fun encode(report:Report):ByteArray = sorted(json.encodeToJsonElement(report)).toString().toByteArray(Charsets.UTF_8)
    fun decode(bytes:ByteArray):Report {
        val raw = json.parseToJsonElement(utf8(bytes)); val report=json.decodeFromJsonElement<Report>(raw)
        val normalized=report.copy(entries=report.entries.map { it.copy(flags=it.flags.distinct().sorted()) })
        require(semanticEqual(raw,json.encodeToJsonElement(normalized))) { "Unsupported or missing report fields; existing report preserved." }
        require(report.entries.size<=100000 && report.entries.map { it.id }.toSet().size==report.entries.size) { "Invalid report identity or duplicate records." }
        return normalized
    }
    private fun semanticEqual(a:JsonElement,b:JsonElement):Boolean = when {
        a is JsonObject && b is JsonObject -> a.keys==b.keys && a.all { (key,value) -> semanticEqual(value,b.getValue(key)) }
        a is JsonArray && b is JsonArray -> a.size==b.size && a.indices.all { semanticEqual(a[it],b[it]) }
        a is JsonPrimitive && b is JsonPrimitive && !a.isString && !b.isString -> {
            val an=a.content.toBigDecimalOrNull();val bn=b.content.toBigDecimalOrNull()
            if (an!=null && bn!=null) an.compareTo(bn)==0 else a==b
        }
        else -> a==b
    }
    fun export(report:Report,device:String):ByteArray {
        val body=encode(report);val manifest=Manifest(reportID=report.id,revision=report.revision,device=device,sha256=digest(body))
        return StoredZIP.write(linkedMapOf("manifest.json" to json.encodeToString(manifest).toByteArray(Charsets.UTF_8),"report.json" to body))
    }
    fun read(bytes:ByteArray):Package {
        val files=StoredZIP.read(bytes)
        require(files.keys==setOf("manifest.json","report.json")) { "Expected manifest.json and report.json. Attachments are unsupported in this alpha." }
        val manifest=manifestJson.decodeFromString<Manifest>(utf8(files.getValue("manifest.json")))
        require(manifest.format=="org.squidproductions.camreport" && manifest.schema==1 && manifest.scope=="full-report") { "Unsupported format, schema or scope; existing report preserved." }
        val body=files.getValue("report.json");require(digest(body)==manifest.sha256) { "Report checksum mismatch." }
        val report=decode(body);require(report.id==manifest.reportID && report.revision==manifest.revision) { "Invalid report identity or revision." }
        return Package(manifest,report)
    }
    fun preview(local:Report,incoming:Package):Preview {
        require(local.id==incoming.report.id) { "Different project. Open as a separate report." }
        if (incoming.manifest.packageID in local.importedPackages) return Preview(emptyList(),emptyList(),true)
        val known=local.entries.associateBy { it.id }
        val additions=incoming.report.entries.filter { it.id !in known }
        val conflicts=incoming.report.entries.filter { it.id in known && known[it.id]!=it }.map { "Scene ${it.values["scene"] ?: "?"} / take ${it.values["take"] ?: "?"} (${it.id.take(8)})" }.toMutableList()
        if (local.values!=incoming.report.values) conflicts+="Project / crew metadata"
        if (local.defaults!=incoming.report.defaults) conflicts+="Camera defaults"
        if (local.profile!=incoming.report.profile || local.positions!=incoming.report.positions || local.namingTemplate!=incoming.report.namingTemplate) conflicts+="Report settings / legacy compatibility data"
        return Preview(additions,conflicts,false)
    }
    fun merge(local:Report,incoming:Package,device:String):Report {
        val p=preview(local,incoming);if (p.duplicate) return local
        require(p.conflicts.isEmpty()) { "Competing changes require review. Open separately; this alpha cannot resolve competing edits." }
        return local.copy(entries=local.entries+p.additions,importedPackages=local.importedPackages+incoming.manifest.packageID).record("Imported ${p.additions.size} additions from ${incoming.manifest.device}",device)
    }
    internal fun utf8(bytes:ByteArray):String = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString()
}

/** Stored ZIP subset, matching the Apple reader. It never extracts archive paths. */
object StoredZIP {
    private fun crc(bytes:ByteArray):Long = CRC32().apply { update(bytes) }.value
    private fun ByteArrayOutputStream.num(value:Long,width:Int) { repeat(width) { write((value ushr (it*8)).toInt() and 255) } }
    private fun ByteArray.value(offset:Int,width:Int):Long {
        require(offset>=0 && offset.toLong()+width<=size) { "Truncated archive." }
        var value=0L;repeat(width) { value=value or ((this[offset+it].toLong() and 255) shl (it*8)) };return value
    }
    fun write(files:Map<String,ByteArray>):ByteArray {
        val output=ByteArrayOutputStream();val directory=ByteArrayOutputStream()
        files.forEach { (name,bytes) ->
            val n=name.toByteArray(Charsets.UTF_8);val offset=output.size().toLong();val check=crc(bytes);val size=bytes.size.toLong()
            listOf(0x04034b50L to 4,20L to 2,0L to 2,0L to 2,0L to 2,0L to 2,check to 4,size to 4,size to 4,n.size.toLong() to 2,0L to 2).forEach { output.num(it.first,it.second) }
            output.write(n);output.write(bytes)
            listOf(0x02014b50L to 4,20L to 2,20L to 2,0L to 2,0L to 2,0L to 2,0L to 2,check to 4,size to 4,size to 4,n.size.toLong() to 2,0L to 2,0L to 2,0L to 2,0L to 2,0L to 4,offset to 4).forEach { directory.num(it.first,it.second) };directory.write(n)
        }
        val start=output.size().toLong();output.write(directory.toByteArray())
        listOf(0x06054b50L to 4,0L to 2,0L to 2,files.size.toLong() to 2,files.size.toLong() to 2,directory.size().toLong() to 4,start to 4,0L to 2).forEach { output.num(it.first,it.second) }
        require(output.size()<=Exchange.LIMIT) { "Report exceeds 32 MiB alpha limit." };return output.toByteArray()
    }
    fun read(bytes:ByteArray):Map<String,ByteArray> {
        require(bytes.size in 22..Exchange.LIMIT) { "Invalid archive size (32 MiB maximum)." }
        var p=0;val files=linkedMapOf<String,ByteArray>();val offsets=mutableMapOf<String,Int>()
        fun v(at:Int,width:Int)=bytes.value(at,width)
        while (v(p,4)==0x04034b50L) {
            require(files.size<8 && v(p+6,2)==0L && v(p+8,2)==0L) { "Only unencrypted stored ZIP is supported." }
            val size=v(p+18,4);val expanded=v(p+22,4);val n=v(p+26,2).toInt();val extra=v(p+28,2).toInt();val begin=p.toLong()+30+n+extra
            require(size==expanded && size<=Exchange.LIMIT && begin<=bytes.size && begin+size<=bytes.size) { "Invalid archive bounds." }
            val name=Exchange.utf8(bytes.copyOfRange(p+30,p+30+n))
            require(name in setOf("manifest.json","report.json") && name !in files) { "Unsafe path or duplicate ZIP entry." }
            val body=bytes.copyOfRange(begin.toInt(),(begin+size).toInt());require(crc(body)==v(p+14,4)) { "Archive CRC mismatch." }
            offsets[name]=p;files[name]=body;p=(begin+size).toInt()
        }
        val directoryStart=p;val seen=mutableSetOf<String>()
        while (v(p,4)==0x02014b50L) {
            val n=v(p+28,2).toInt();val extra=v(p+30,2).toInt();val comment=v(p+32,2).toInt()
            require(p.toLong()+46+n+extra+comment<=bytes.size) { "Invalid directory bounds." }
            val name=Exchange.utf8(bytes.copyOfRange(p+46,p+46+n));val body=files[name] ?: throw ReportException("Unknown directory entry.")
            require(name !in seen && offsets[name]?.toLong()==v(p+42,4) && crc(body)==v(p+16,4) && body.size.toLong()==v(p+20,4) && body.size.toLong()==v(p+24,4) && v(p+10,2)==0L && v(p+8,2)==0L && v(p+34,2)==0L) { "Invalid archive directory." }
            seen+=name;p+=46+n+extra+comment
        }
        require(v(p,4)==0x06054b50L && p+22==bytes.size && v(p+4,4)==0L && v(p+8,2)==files.size.toLong() && v(p+10,2)==files.size.toLong() && v(p+12,4)==(p-directoryStart).toLong() && v(p+16,4)==directoryStart.toLong() && v(p+20,2)==0L && seen.size==files.size) { "Incomplete or unsupported ZIP directory." }
        return files
    }
}
