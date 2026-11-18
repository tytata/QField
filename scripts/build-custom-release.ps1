[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$VersionCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VersionName,

    [switch]$BuildDockerImage
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
$BuildVolume = "qfield-build-arm64"
$GradleVolume = "qfield-gradle-cache"
$DockerImage = "qfield_and_dev"
$ArtifactDirectory = Join-Path $RepoRoot "artifacts"
$KeystorePropertiesPath = Join-Path $RepoRoot "platform\android\keystore.properties"
$KeystorePath = "/usr/src/qfield/platform/android/keystores/qfield-dev.keystore"
$UnsignedApk = "/usr/src/qfield/artifacts/android-build-release-custom-unsigned.apk"
$SignedApk = "/usr/src/qfield/artifacts/android-build-release-custom-v$VersionCode.apk"

if ($VersionName.Contains("'") -or $VersionName.Contains('"')) {
    throw "VersionName không được chứa dấu nháy đơn hoặc nháy kép."
}

if (-not (Test-Path $KeystorePropertiesPath)) {
    throw "Không tìm thấy $KeystorePropertiesPath. Hãy copy keystore.properties vào platform/android."
}

$KeystoreProperties = @{}
Get-Content $KeystorePropertiesPath | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*)\s*$") {
        $KeystoreProperties[$matches[1].Trim()] = $matches[2].Trim()
    }
}

foreach ($RequiredProperty in @("storePassword", "keyPassword", "keyAlias")) {
    if (-not $KeystoreProperties.ContainsKey($RequiredProperty)) {
        throw "Thiếu $RequiredProperty trong keystore.properties."
    }
}

if (-not (Test-Path (Join-Path $RepoRoot "platform\android\keystores\qfield-dev.keystore"))) {
    throw "Không tìm thấy keystore dev."
}

Set-Location $RepoRoot
New-Item -ItemType Directory -Force $ArtifactDirectory | Out-Null

function Invoke-DockerBash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$ExtraArguments = @()
    )

    $DockerArguments = @(
        "run", "--rm",
        "-v", "${RepoRoot}:/usr/src/qfield",
        "-v", "${BuildVolume}:/usr/src/build",
        "-v", "${GradleVolume}:/root/.gradle"
    )
    $DockerArguments += $ExtraArguments
    # PowerShell on Windows uses CRLF. Normalize before passing the command to
    # Bash so a trailing carriage return cannot break line continuations or
    # become part of an argument.
    $NormalizedCommand = $Command -replace "`r`n", "`n"
    $NormalizedCommand = $NormalizedCommand -replace "`r", ""
    $DockerArguments += @($DockerImage, "bash", "-lc", $NormalizedCommand)

    & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build step thất bại với exit code $LASTEXITCODE."
    }
}

Write-Host "[1/5] Kiểm tra Docker image và volume..." -ForegroundColor Cyan

$OriginalErrorActionPreference = $ErrorActionPreference
try {
    # A missing image is expected on a new machine; inspect it via exit code.
    $ErrorActionPreference = "Continue"
    & docker image inspect $DockerImage *> $null
    $ImageInspectExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $OriginalErrorActionPreference
}

if ($ImageInspectExitCode -ne 0 -or $BuildDockerImage) {
    Write-Host "Đang build Docker image $DockerImage..." -ForegroundColor Yellow
    & docker build (Join-Path $RepoRoot ".docker\android_dev") -t $DockerImage
    if ($LASTEXITCODE -ne 0) {
        throw "Không build được Docker image."
    }
}

foreach ($Volume in @($BuildVolume, $GradleVolume)) {
    $OriginalErrorActionPreference = $ErrorActionPreference
    try {
        # Missing volumes are expected; use the exit code to create them below.
        $ErrorActionPreference = "Continue"
        & docker volume inspect $Volume *> $null
        $VolumeInspectExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OriginalErrorActionPreference
    }

    if ($VolumeInspectExitCode -ne 0) {
        & docker volume create $Volume
        if ($LASTEXITCODE -ne 0) {
            throw "Không tạo được Docker volume $Volume."
        }
    }
}

Write-Host "[2/5] Configure và compile source..." -ForegroundColor Cyan
$BuildCommand = @"
set -e
cmake -S /usr/src/qfield -B /usr/src/build -G Ninja -DAPP_PACKAGE_NAME=qfield -DCMAKE_BUILD_TYPE=Release -DANDROID_SDK_ROOT=/android-sdk -DVCPKG_TARGET_TRIPLET=arm64-android -DWITH_SPIX=OFF -DWITH_ALL_FILES_ACCESS=OFF -DAPK_VERSION_CODE=$VersionCode -DAPP_VERSION_STR='$VersionName'
cmake --build /usr/src/build --target qfield -j2
"@
Invoke-DockerBash $BuildCommand

Write-Host "[3/5] Đóng gói APK release unsigned..." -ForegroundColor Cyan
$PackageCommand = @"
set -e
mkdir -p /usr/src/build/src/app/android-build/libs/arm64-v8a
cp /usr/src/build/android-build/lib/libqfield_arm64-v8a.so /usr/src/build/src/app/android-build/libs/arm64-v8a/
/usr/src/build/vcpkg_installed/x64-linux/tools/Qt6/bin/androiddeployqt --input /usr/src/build/src/app/android-qfield-deployment-settings.json --output /usr/src/build/src/app/android-build --deployment bundled --android-platform android-36 --gradle --release
cp /usr/src/build/src/app/android-build/build/outputs/apk/release/android-build-release-unsigned.apk $UnsignedApk
"@
Invoke-DockerBash $PackageCommand

Write-Host "[4/5] Ký APK bằng keystore custom..." -ForegroundColor Cyan
$SigningArguments = @(
    "-e", "STOREPASS=$($KeystoreProperties.storePassword)",
    "-e", "KEYPASS=$($KeystoreProperties.keyPassword)"
)
$SigningCommand = @"
set -e
/android-sdk/build-tools/35.0.1/apksigner sign --ks $KeystorePath --ks-key-alias $($KeystoreProperties.keyAlias) --ks-pass pass:`$STOREPASS --key-pass pass:`$KEYPASS --out $SignedApk $UnsignedApk
"@
Invoke-DockerBash $SigningCommand $SigningArguments

Write-Host "[5/5] Kiểm tra chữ ký APK..." -ForegroundColor Cyan
$VerifyCommand = @"
set -e
/android-sdk/build-tools/35.0.1/apksigner verify --verbose --print-certs $SignedApk
"@
Invoke-DockerBash $VerifyCommand

$LocalSignedApk = Join-Path $ArtifactDirectory "android-build-release-custom-v$VersionCode.apk"
Write-Host "Build thành công: $LocalSignedApk" -ForegroundColor Green
