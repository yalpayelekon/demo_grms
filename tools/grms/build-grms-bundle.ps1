param(
    [ValidateSet("release", "debug")]
    [string]$Configuration = "release",
    [string]$FrontendApiBaseUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-Info {
    param([string]$Message)
    Write-Host "[grms-bundle] $Message"
}

function Resolve-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $root = Resolve-Path (Join-Path $scriptDir "..\..")
    return $root
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Clear-DirectoryContents {
    param([string]$Path)
    Ensure-Directory -Path $Path
    Get-ChildItem -LiteralPath $Path -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

function Assert-CommandExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description not found at $Path"
    }
}

function Build-TestCommGo {
    param(
        [string]$ProjectPath,
        [string]$OutputExe
    )
    Write-Info "Building testcomm_go..."
    Set-Location $ProjectPath
    go build -o $OutputExe .
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed with exit code $LASTEXITCODE"
    }
}

function Build-FlutterGrems {
    param(
        [string]$ProjectPath,
        [string]$Configuration,
        [string]$FrontendApiBaseUrl
    )
    Write-Info "Building flutter_grems_app web bundle..."
    Set-Location $ProjectPath

    if (-not (Test-Path -LiteralPath "pubspec.yaml")) {
        throw "pubspec.yaml not found in $ProjectPath"
    }

    & flutter pub get 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }

    $buildArgs = @("build", "web", "--no-pub", "--release", "--base-href", "/")
    if ($Configuration -ieq "debug") {
        $buildArgs = @("build", "web", "--no-pub", "--base-href", "/")
    }

    $buildArgs += @("--dart-define=GREMS_DEPLOYMENT_MODE=deployed")
    if (-not [string]::IsNullOrWhiteSpace($FrontendApiBaseUrl)) {
        $buildArgs += @("--dart-define=TESTCOMM_BASE_URL=$FrontendApiBaseUrl")
    }

    & flutter @buildArgs 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build web failed with exit code $LASTEXITCODE"
    }
}

function Build-GrmsLauncher {
    param(
        [string]$LauncherPath,
        [string]$OutputExe
    )
    Write-Info "Building grms_launcher.exe..."
    Set-Location $LauncherPath
    go build -o $OutputExe .
    if ($LASTEXITCODE -ne 0) {
        throw "go build for grms_launcher failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = Resolve-RepoRoot
Write-Info "Repository root: $repoRoot"

$flutterAppPath = Join-Path $repoRoot "tools\\grms\\flutter_grems_app"
$testcommPath = Join-Path $repoRoot "tools\\grms\\testcomm_go"
$launcherPath = Join-Path $repoRoot "tools\\grms\\grms_launcher"
$testcommConfigPath = Join-Path $testcommPath "config"
$distPath = Join-Path $repoRoot "dist\\grms_bundle"
$backendOutDir = Join-Path $distPath "backend"
$frontendOutDir = Join-Path $distPath "frontend\\web"
$launcherOutDir = Join-Path $distPath "launcher"

Write-Info "Checking prerequisites..."
Assert-CommandExists -Name "go"
Assert-CommandExists -Name "flutter"
Assert-PathExists -Path $flutterAppPath -Description "Flutter GRMS app path"
Assert-PathExists -Path $testcommPath -Description "TestComm Go path"
Assert-PathExists -Path $launcherPath -Description "Launcher project path"
Assert-PathExists -Path $testcommConfigPath -Description "TestComm config path"

Write-Info "Preparing output directories..."
Ensure-Directory -Path $distPath
Clear-DirectoryContents -Path $backendOutDir
Clear-DirectoryContents -Path $frontendOutDir
Clear-DirectoryContents -Path $launcherOutDir
Remove-Item -LiteralPath (Join-Path $distPath "Start-GRMS.ps1") -Force -ErrorAction SilentlyContinue

$backendExePath = Join-Path $backendOutDir "testcomm_go.exe"
$launcherExePath = Join-Path $launcherOutDir "grms_launcher.exe"

Set-Location $repoRoot

Build-TestCommGo -ProjectPath $testcommPath -OutputExe $backendExePath
Build-FlutterGrems -ProjectPath $flutterAppPath -Configuration $Configuration -FrontendApiBaseUrl $FrontendApiBaseUrl

Write-Info "Copying TestComm runtime config into bundle..."
$backendConfigOutDir = Join-Path $backendOutDir "config"
Ensure-Directory -Path $backendConfigOutDir
Copy-Item -Path (Join-Path $testcommConfigPath "*") -Destination $backendConfigOutDir -Recurse -Force

Write-Info "Copying Flutter web build output into bundle..."
$webBuildPath = Join-Path $flutterAppPath "build\\web"
Assert-PathExists -Path $webBuildPath -Description "Flutter web build output"
Copy-Item -Path (Join-Path $webBuildPath "*") -Destination $frontendOutDir -Recurse -Force

Write-Info "Building launcher executable..."
Build-GrmsLauncher -LauncherPath $launcherPath -OutputExe $launcherExePath

Write-Info "GRMS bundle built successfully."
Write-Info "Bundle location: $distPath"
Write-Info "To run, open a PowerShell window, cd to the bundle and run:"
Write-Host "  .\\launcher\\grms_launcher.exe" -ForegroundColor Green


