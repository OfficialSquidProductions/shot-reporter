package org.squidproductions.camerastats.desktop

import org.squidproductions.camerastats.core.*
import java.nio.file.*

/** Reporting-only QA, confined to a fresh runner directory and fictional report data. */
fun windowsDesktopReleaseSmoke(output:Path) {
    check(!Files.exists(output));Files.createDirectories(output)
    packagedSelfTest(output)
    val report=Exchange.read(Files.readAllBytes(output.resolve("package-test.camreport"))).report
    check(report.active.size==4)
    val csv=Reports.csv(report);val html=Reports.html(report)
    check(csv.contains("scene") && csv.contains("take"))
    check(html.contains("Runtime QA report") && html.contains("<table>"))
    durableExport(output.resolve("package-test.csv"),csv.toByteArray(Charsets.UTF_8))
    durableExport(output.resolve("package-test.html"),html.toByteArray(Charsets.UTF_8))
    Files.writeString(output.resolve("PASS.txt"),"PASS: bundled runtime, durable report reopen, next take, camreport roundtrip, PDF, CSV and HTML report exports.\n")
}
