param([Parameter(Mandatory=$true)][string]$MSI,[Parameter(Mandatory=$true)][string]$PackagedLauncher,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $Output | Out-Null
function RunApp([string]$launcher,[string[]]$arguments,[string]$pass) {
    $p=Start-Process -FilePath $launcher -ArgumentList $arguments -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pass)) {throw "Runtime smoke failed ($($p.ExitCode)): $launcher"}
    Get-Content -LiteralPath $pass
}
$qa=Join-Path $Output 'packaged'
RunApp $PackagedLauncher @('--self-test',('"'+$qa+'"')) (Join-Path $qa 'PASS.txt')
RunApp $PackagedLauncher @('--desktop-release-smoke',('"'+(Join-Path $Output 'packaged-reporting')+'"')) (Join-Path $Output 'packaged-reporting/PASS.txt')
$oldDir=Join-Path $Output 'previous'
gh release download v0.2.0-alpha.2 --repo $env:GITHUB_REPOSITORY --pattern Shot-Reporter-Windows-0.2.0-alpha.2.msi --dir $oldDir
if ($LASTEXITCODE -ne 0) {throw 'Previous public MSI download failed'}
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
$old=Join-Path $oldDir 'Shot-Reporter-Windows-0.2.0-alpha.2.msi'
if ((Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash.ToLowerInvariant() -ne '4937733b4b70ddcd5ed70a6ce8dd72ebee7a6d48e1dd6af4a78adabe2142fa78') {throw 'Previous MSI hash mismatch'}
# All report data is confined to a fresh synthetic profile, never the runner user's existing data.
$env:LOCALAPPDATA=Join-Path $Output 'isolated-profile'
New-Item -ItemType Directory -Path $env:LOCALAPPDATA | Out-Null
$p=Start-Process "$env:SystemRoot/System32/msiexec.exe" -ArgumentList @('/i',('"'+$old+'"'),'/qn','/norestart','/L*v',('"'+(Join-Path $Output 'previous-install.log')+'"')) -Wait -PassThru
if ($p.ExitCode -notin 0,3010) {throw "Previous MSI installation failed: $($p.ExitCode)"}
$installed=Join-Path $env:ProgramFiles 'Shot Reporter/Shot Reporter.exe'
$oldQA=Join-Path $Output 'old-runtime'
RunApp $installed @('--self-test',('"'+$oldQA+'"')) (Join-Path $oldQA 'PASS.txt')
$data=Join-Path $env:LOCALAPPDATA 'Squid Productions/Camera Stats';New-Item -ItemType Directory -Path $data | Out-Null
Copy-Item -LiteralPath (Join-Path $oldQA 'qa.sqlite3') -Destination (Join-Path $data 'reports.sqlite3')
Set-Content -LiteralPath (Join-Path $data 'preferences.properties') -Value 'theme=Dark'
if ((Get-AuthenticodeSignature -LiteralPath $MSI).Status -ne 'NotSigned') {throw 'This release expects an unsigned manual installer; review publisher policy before changing this gate'}
$p=Start-Process "$env:SystemRoot/System32/msiexec.exe" -ArgumentList @('/i',('"'+$MSI+'"'),'/qn','/norestart','/L*v',('"'+(Join-Path $Output 'upgrade-install.log')+'"')) -Wait -PassThru
if ($p.ExitCode -notin 0,3010) {throw "New MSI installation failed: $($p.ExitCode)"}
$installedQA=Join-Path $Output 'installed-runtime'
RunApp $installed @('--self-test',('"'+$installedQA+'"')) (Join-Path $installedQA 'PASS.txt')
$upgrade=Join-Path $Output 'upgrade'
RunApp $installed @('--verify-report-upgrade',('"'+(Join-Path $oldQA 'package-test.camreport')+'"'),('"'+$upgrade+'"')) (Join-Path $upgrade 'PASS.txt')
$reporting=Join-Path $Output 'installed-reporting'
RunApp $installed @('--desktop-release-smoke',('"'+$reporting+'"')) (Join-Path $reporting 'PASS.txt')
$products=@(Get-ItemProperty 'HKLM:/Software/Microsoft/Windows/CurrentVersion/Uninstall/*' | Where-Object {$_.DisplayName -eq 'Shot Reporter'})
if ($products.Count -ne 1 -or $products[0].DisplayVersion -ne '0.2.2') {throw 'Installed product version/upgrade identity is not unique 0.2.2'}
Set-Content -LiteralPath (Join-Path $Output 'PASS.txt') -Value 'PASS: previous 0.2.0-alpha.2/MSI 0.2.1 -> 0.2.0-alpha.6/MSI 0.2.2 install, isolated report/history/preferences preservation, packaged and installed reporting smoke. Successful signed auto-update remains unvalidated.'
