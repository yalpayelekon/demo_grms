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

function Invoke-NativeLogged {
    # Flutter (and other tools) write progress/warnings to stderr. With
    # $ErrorActionPreference=Stop, `2>&1` turns those into terminating ErrorRecords.
    # Stream output safely and rely on $LASTEXITCODE for success/failure.
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $_.ToString()
            } else {
                Write-Host $_
            }
        }
    } finally {
        $ErrorActionPreference = $previous
    }
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

function Initialize-GoCgoToolchain {
    # testcomm_go depends on github.com/mattn/go-sqlite3, which requires CGO + a working
    # MinGW gcc on Windows. A common failure mode is CC pointing at MSYS2 gcc while a
    # different gcc (e.g. Scoop) is first on PATH — cgo then exits with status 2 and no
    # useful message. Pin CC/CXX to one compiler and put its bin dir first on PATH.
    Assert-CommandExists -Name "gcc"

    $gccPath = $null
    if (-not [string]::IsNullOrWhiteSpace($env:CC) -and (Test-Path -LiteralPath $env:CC)) {
        $gccPath = (Resolve-Path -LiteralPath $env:CC).Path
    } else {
        $gccPath = (Get-Command gcc).Source
    }

    $gccDir = Split-Path -Parent $gccPath
    $gppPath = Join-Path $gccDir "g++.exe"
    if (-not (Test-Path -LiteralPath $gppPath)) {
        $gppCmd = Get-Command g++ -ErrorAction SilentlyContinue
        if ($gppCmd) {
            $gppPath = $gppCmd.Source
        } else {
            throw "g++ not found next to gcc at $gccDir (required for CGO builds)."
        }
    }

    $env:CC = $gccPath
    $env:CXX = $gppPath
    $env:CGO_ENABLED = "1"
    $env:PATH = "$gccDir;$env:PATH"

    Write-Info "Using CGO toolchain: CC=$env:CC"
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

    Invoke-NativeLogged { flutter pub get }
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }

    # --no-web-resources-cdn bundles CanvasKit locally so the app works on LANs
    # without internet access.
    $buildArgs = @("build", "web", "--no-pub", "--release", "--base-href", "/", "--no-wasm-dry-run", "--no-web-resources-cdn")
    if ($Configuration -ieq "debug") {
        $buildArgs = @("build", "web", "--no-pub", "--base-href", "/", "--no-wasm-dry-run", "--no-web-resources-cdn")
    }

    $buildArgs += @("--dart-define=GREMS_DEPLOYMENT_MODE=deployed")
    if (-not [string]::IsNullOrWhiteSpace($FrontendApiBaseUrl)) {
        $buildArgs += @("--dart-define=TESTCOMM_BASE_URL=$FrontendApiBaseUrl")
    }

    Invoke-NativeLogged { flutter @buildArgs }
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
Initialize-GoCgoToolchain

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
Write-Info "To run:"
Write-Host "  cd `"$distPath`"" -ForegroundColor Green
Write-Host "  .\launcher\grms_launcher.exe" -ForegroundColor Green


