<#
  build-hap.ps1 - Build the HAP with the hvigor / node / SDK bundled with DevEco Studio.

  Why this script exists: a fresh clone has no hvigorw wrapper on PATH, so the
  README command `hvigorw ...` only works inside DevEco's own terminal. This
  script locates DevEco Studio, points hvigor at an in-project cache
  (.hvigor-home, gitignored) and runs assembleHap, so the command line build
  works on a clean machine with only DevEco installed.

  Usage (from the repository root):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1 -BuildMode release
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1 -Clean

  Output:
    entry/build/default/outputs/default/entry-default-unsigned.hap

  Note: the HAP is unsigned. Configure signing in DevEco Studio
  (File -> Project Structure -> Signing Configs) before installing on a device.
#>
param(
  [string]$DevEcoHome = 'D:\Program Files\Huawei\DevEco Studio',
  [ValidateSet('debug', 'release')][string]$BuildMode = 'debug',
  # default = 手机（含手表模块的 App Pack）；wearable = 只打手表模块
  [ValidateSet('default', 'wearable')][string]$Product = 'default',
  [switch]$Clean
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $DevEcoHome)) {
  throw "DevEco Studio not found: $DevEcoHome (pass -DevEcoHome <path>)"
}
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
$hvigorw = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
$sdk = Join-Path $DevEcoHome 'sdk'
if (-not (Test-Path $node)) { throw "node not found: $node" }
if (-not (Test-Path $hvigorw)) { throw "hvigor not found: $hvigorw" }
if (-not (Test-Path $sdk)) { throw "SDK not found: $sdk" }

$project = Split-Path -Parent $PSCommandPath
$hvigorHome = Join-Path $project '.hvigor-home'
New-Item -ItemType Directory -Force -Path $hvigorHome | Out-Null

$env:DEVECO_SDK_HOME = $sdk
$env:NODE_HOME = Join-Path $DevEcoHome 'tools\node'
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:HVIGOR_USER_HOME = $hvigorHome
$env:PATH = "$env:NODE_HOME;$(Join-Path $DevEcoHome 'tools\ohpm\bin');$(Join-Path $sdk 'default\openharmony\toolchains');$env:PATH"

Push-Location $project
try {
  if ($Clean) {
    Write-Host '>> hvigor clean' -ForegroundColor Cyan
    & $node $hvigorw clean --no-daemon 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "clean failed (exit $LASTEXITCODE)" }
  }

  Write-Host ">> hvigor assembleHap (product=$Product mode=$BuildMode)" -ForegroundColor Cyan
  & $node $hvigorw assembleHap --mode module -p "product=$Product" -p "buildMode=$BuildMode" --no-daemon 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }

  $module = if ($Product -eq 'wearable') { 'wearable' } else { 'entry' }
  # 模块内 HAP 落在 <module>/build/<module>/outputs/default/，不是 build/default/outputs/。
  $hap = Join-Path $project "$module\build\$module\outputs\default\$module-default-unsigned.hap"
  if (-not (Test-Path $hap)) {
    $hap = Join-Path $project "$module\build\default\outputs\default\$module-default-unsigned.hap"
  }
  if (Test-Path $hap) {
    $size = [math]::Round((Get-Item $hap).Length / 1MB, 2)
    Write-Host ''
    Write-Host "BUILD OK: $hap ($size MB)" -ForegroundColor Green
    Write-Host 'The HAP is unsigned; configure signing in DevEco before installing.' -ForegroundColor Yellow
  } else {
    Write-Host 'Build finished but the expected HAP was not found. Check the log above.' -ForegroundColor Yellow
  }
} finally {
  Pop-Location
}

exit 0
