package org.squidproductions.camerastats.updates

import kotlinx.serialization.*
import java.nio.file.*
import java.util.Base64

@Serializable data class InstallTicket(val schema:Int=1,val appID:String=APPLICATION_ID,val parentPID:Long,val installer:String,val sha256:String,val size:Long,val signerSHA256:String,val upgradeCode:String=MSI_UPGRADE_CODE,val msiVersion:String,val relaunch:String,val version:String,val build:Long)
@Serializable data class UpdateInstallResult(val schema:Int=1,val success:Boolean,val error:String?=null,val exitCode:Int?=null,val version:String?=null,val build:Long?=null,val finishedAt:String)
fun installResultMessage(result:UpdateInstallResult):String {
    check(result.schema==1) {"Unknown update result format. Recovery files were retained."}
    return when {
        result.success && result.exitCode==3010 -> "Shot Reporter ${result.version.orEmpty()} was installed. Windows reports that a restart is required; Shot Reporter did not restart your computer."
        result.success -> "Shot Reporter ${result.version.orEmpty()} was installed. Recovery snapshots and installer logs are retained."
        result.exitCode==1602 -> "Windows Installer reported that the update was cancelled. Installer logs and pre-update recovery snapshots are retained."
        else -> "The update did not complete. ${result.error?.take(1000) ?: "Review the installer log before trying again."} Installer logs and pre-update recovery snapshots are retained."
    }
}
/** Injectable for isolated orchestration tests; production only launches the Windows system helper. */
fun interface InstallerLauncher {fun launch(ticket:Path)}
class WindowsInstallerLauncher:InstallerLauncher {
    override fun launch(ticket:Path) {
        check(System.getProperty("os.name").startsWith("Windows")) {"Windows installation is only available on Windows."}
        val system=Path.of(System.getenv("SystemRoot") ?: error("Windows system folder unavailable."))
        val shell=system.resolve("System32/WindowsPowerShell/v1.0/powershell.exe")
        check(Files.isRegularFile(shell,LinkOption.NOFOLLOW_LINKS))
        val command=Base64.getEncoder().encodeToString(windowsInstallScript.toByteArray(Charsets.UTF_16LE))
        val builder=ProcessBuilder(shell.toString(),"-NoLogo","-NoProfile","-NonInteractive","-EncodedCommand",command)
        // A pwsh7 parent can supply an incompatible module path. Only OS PowerShell modules may implement trust checks.
        builder.environment()["PSModulePath"]=system.resolve("System32/WindowsPowerShell/v1.0/Modules").toString()
        builder.environment()["SHOT_REPORTER_UPDATE_TICKET"]=ticket.toAbsolutePath().toString()
        builder.redirectErrorStream(true);builder.redirectOutput(ticket.parent.resolve("helper.log").toFile());val helper=builder.start()
        // Readiness is preflight only. Without an explicit commit, parent death cannot start MSI.
        val ready=ticket.parent.resolve("helper-ready.txt");val deadline=System.nanoTime()+120_000_000_000L
        fun acknowledged()=runCatching {Files.isRegularFile(ready,LinkOption.NOFOLLOW_LINKS) && Files.readString(ready).trim()=="ready"}.getOrDefault(false)
        try {
            while(!acknowledged() && !Files.exists(ticket.parent.resolve("install-result.json")) && helper.isAlive && System.nanoTime()<deadline) Thread.sleep(50)
            check(acknowledged()) {"Installer helper could not verify this package. Shot Reporter stays open; inspect retained helper logs."}
        } catch(e:Throwable) {
            runCatching {durableNew(ticket.parent.resolve("install-cancelled.txt"),"cancelled\n".toByteArray())}
            helper.destroy();throw e
        }
    }
}
class WindowsUpdateInstaller(private val policy:UpdatePolicy,private val launcher:InstallerLauncher=WindowsInstallerLauncher()) {
    /** saveAndQuiesce must verify durable reports and back up the report database before exit. */
    fun prepare(release:UpdateRelease,installer:Path,relaunch:Path,saveAndQuiesce:()->AutoCloseable):PreparedInstall {
        policy.validate();val asset=checkNotNull(release.windowsX64)
        check(Files.isRegularFile(installer,LinkOption.NOFOLLOW_LINKS) && !Files.isSymbolicLink(installer) && Files.size(installer)==asset.size && sha256(installer).equals(asset.sha256,true)) {"Staged installer changed. Download it again."}
        check(asset.signerSHA256.equals(policy.signerSHA256,true) && asset.upgradeCode.equals(MSI_UPGRADE_CODE,true))
        check(Files.isRegularFile(relaunch,LinkOption.NOFOLLOW_LINKS) && relaunch.fileName.toString().equals("Shot Reporter.exe",true)) {"Run the installed Shot Reporter application before installing an update."}
        val guard=saveAndQuiesce()
        try {
            val ticket=InstallTicket(parentPID=ProcessHandle.current().pid(),installer=installer.toRealPath().toString(),sha256=asset.sha256,size=asset.size,signerSHA256=policy.signerSHA256,msiVersion=asset.msiVersion,relaunch=relaunch.toRealPath().toString(),version=release.version,build=release.build)
            val attempt=installer.parent.resolve("install-"+java.util.UUID.randomUUID().toString());Files.createDirectory(attempt)
            val path=attempt.resolve("install-ticket.json");durableNew(path,updateJSON.encodeToString(ticket).toByteArray());launcher.launch(path);return PreparedInstall(path,guard)
        } catch(e:Throwable) {guard.close();throw e}
    }
}
/** A separate durable commit is required after preflight and before the UI requests exit. */
class PreparedInstall internal constructor(val ticket:Path,private val saveGuard:AutoCloseable):AutoCloseable {
    private var committed=false
    private var closed=false
    @Synchronized fun commit() {
        check(!closed) {"Update handoff was cancelled; Shot Reporter stays open."}
        if(!committed) {
            val pending=ticket.parent.resolve("install-commit.partial")
            durableNew(pending,"committed\n".toByteArray())
            Files.move(pending,ticket.parent.resolve("install-committed.txt"),StandardCopyOption.ATOMIC_MOVE)
            committed=true
        }
    }
    @Synchronized override fun close() {
        if(closed) return
        closed=true
        if(!committed) runCatching {durableNew(ticket.parent.resolve("install-cancelled.txt"),"cancelled\n".toByteArray())}
        saveGuard.close()
    }
}
/** No execution-policy bypass. Trust is checked again after the original process exits, before MSI starts.
 * MSI owns transaction rollback. Neither the helper nor MSI is passed the user's data-directory path. */
val windowsInstallScript="""
${'$'}ErrorActionPreference = 'Stop'
${'$'}ticketPath = ${'$'}env:SHOT_REPORTER_UPDATE_TICKET
${'$'}homePath = Split-Path -LiteralPath ${'$'}ticketPath
${'$'}resultPath = Join-Path ${'$'}homePath 'install-result.json'
${'$'}t = ${'$'}null
${'$'}parentExited = ${'$'}false
${'$'}installerLock = ${'$'}null
${'$'}installerExitCode = ${'$'}null
function CertSHA(${'$'}cert) { return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(${'$'}cert.RawData))).Replace('-','').ToLowerInvariant() }
function WriteResult(${'$'}value) {
    ${'$'}pending = Join-Path ${'$'}homePath 'install-result.partial'
    ${'$'}bytes = [Text.Encoding]::UTF8.GetBytes((${'$'}value | ConvertTo-Json))
    ${'$'}stream = [IO.File]::Open(${'$'}pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { ${'$'}stream.Write(${'$'}bytes,0,${'$'}bytes.Length); ${'$'}stream.Flush(${'$'}true) } finally { ${'$'}stream.Dispose() }
    [IO.File]::Move(${'$'}pending,${'$'}resultPath)
}
try {
    foreach (${'$'}module in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Security')) {
        Import-Module -Name (Join-Path ${'$'}PSHOME ('Modules/' + ${'$'}module + '/' + ${'$'}module + '.psd1')) -ErrorAction Stop
    }
    ${'$'}t = Get-Content -LiteralPath ${'$'}ticketPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (${'$'}t.schema -ne 1 -or ${'$'}t.appID -ne 'org.squidproductions.camerastats') { throw 'Invalid install ticket.' }
    function VerifyInstaller {
    ${'$'}others = @(Get-Process -Name 'Shot Reporter','Camera Stats','CameraStats' -ErrorAction SilentlyContinue | Where-Object { ${'$'}_.Id -ne ${'$'}t.parentPID })
    if (${'$'}others.Count -gt 0) { throw 'Close other Shot Reporter or Camera Stats instances before installing an update.' }
    ${'$'}item = Get-Item -LiteralPath ${'$'}t.installer
    if ((${'$'}item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ${'$'}item.Length -ne ${'$'}t.size) { throw 'Installer identity changed.' }
    if ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath ${'$'}t.installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne ${'$'}t.sha256.ToLowerInvariant()) { throw 'Installer SHA-256 mismatch.' }
    ${'$'}signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath ${'$'}t.installer
    if (${'$'}signature.Status -ne 'Valid' -or (CertSHA ${'$'}signature.SignerCertificate) -ne ${'$'}t.signerSHA256.ToLowerInvariant()) { throw 'Installer publisher verification failed.' }
    ${'$'}engine = New-Object -ComObject WindowsInstaller.Installer
    ${'$'}db = ${'$'}engine.OpenDatabase(${'$'}t.installer,0)
    function Property(${'$'}name) { ${'$'}view = ${'$'}db.OpenView(('SELECT `Value` FROM `Property` WHERE `Property` = ' + "'" + ${'$'}name + "'")); ${'$'}view.Execute(); return ${'$'}view.Fetch().StringData(1) }
    if ((Property 'UpgradeCode').Trim('{}').ToLowerInvariant() -ne 'c3774fda-7962-4264-a9bc-c428176d12b4' -or (Property 'ProductName') -ne 'Shot Reporter' -or (Property 'ProductVersion') -ne ${'$'}t.msiVersion) { throw 'MSI app identity or version mismatch.' }
    if (-not ${'$'}db.SummaryInformation(0).Property(7).StartsWith('x64')) { throw 'MSI architecture mismatch.' }
    ${'$'}db = ${'$'}null; ${'$'}engine = ${'$'}null; [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    ${'$'}installerLock = [IO.File]::Open(${'$'}t.installer,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    VerifyInstaller
    'ready' | Set-Content -LiteralPath (Join-Path ${'$'}homePath 'helper-ready.txt') -Encoding ASCII
    ${'$'}parent = Get-Process -Id ${'$'}t.parentPID -ErrorAction SilentlyContinue
    ${'$'}deadline = [DateTime]::UtcNow.AddMinutes(2)
    while (${'$'}parent -and -not ${'$'}parent.HasExited) {
        if (Test-Path -LiteralPath (Join-Path ${'$'}homePath 'install-cancelled.txt')) { throw 'Update handoff cancelled.' }
        if ([DateTime]::UtcNow -ge ${'$'}deadline) { throw 'App did not close; installation cancelled.' }
        Start-Sleep -Milliseconds 100
        ${'$'}parent.Refresh()
    }
    ${'$'}parentExited = ${'$'}true
    if ((Test-Path -LiteralPath (Join-Path ${'$'}homePath 'install-cancelled.txt')) -or -not (Test-Path -LiteralPath (Join-Path ${'$'}homePath 'install-committed.txt'))) { throw 'Update handoff was never committed; installation cancelled.' }
    if ((Get-Content -LiteralPath (Join-Path ${'$'}homePath 'install-committed.txt') -Raw -Encoding UTF8).Trim() -ne 'committed') { throw 'Invalid update commit marker.' }
    VerifyInstaller
    ${'$'}log = Join-Path ${'$'}homePath 'msi-install.log'
    ${'$'}arguments = '/i "' + ${'$'}t.installer + '" /qb /norestart REBOOT=ReallySuppress /L*v "' + ${'$'}log + '"'
    ${'$'}p = Start-Process -FilePath (Join-Path ${'$'}env:SystemRoot 'System32/msiexec.exe') -ArgumentList ${'$'}arguments -Wait -PassThru
    ${'$'}installerExitCode = ${'$'}p.ExitCode
    ${'$'}ok = ${'$'}p.ExitCode -eq 0 -or ${'$'}p.ExitCode -eq 3010
    if (-not ${'$'}ok) { throw ('Windows Installer returned ' + ${'$'}p.ExitCode + '. Original data and update logs retained.') }
    WriteResult @{schema=1;success=${'$'}true;exitCode=${'$'}p.ExitCode;version=${'$'}t.version;build=${'$'}t.build;finishedAt=[DateTime]::UtcNow.ToString('o')}
} catch {
    WriteResult @{schema=1;success=${'$'}false;exitCode=${'$'}installerExitCode;version=${'$'}t.version;build=${'$'}t.build;error=${'$'}_.Exception.Message;finishedAt=[DateTime]::UtcNow.ToString('o')}
} finally {
    if (${'$'}installerLock) { ${'$'}installerLock.Dispose() }
    if (${'$'}parentExited -and ${'$'}t -and (Test-Path -LiteralPath ${'$'}t.relaunch -PathType Leaf)) { Start-Process -FilePath ${'$'}t.relaunch }
}
"""
