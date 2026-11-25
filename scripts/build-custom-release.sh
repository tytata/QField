#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/build-custom-release.sh -VersionCode <number> -VersionName <name> [-BuildDockerImage]

Options:
  -VersionCode       Positive Android version code (maximum 2147483647)
  -VersionName       Version name embedded in the APK
  -BuildDockerImage  Rebuild the qfield_and_dev Docker image
  -h, --help         Show this help
EOF
}

fail() {
  printf 'Lỗi: %s\n' "$*" >&2
  exit 1
}

VERSION_CODE=
VERSION_NAME=
BUILD_DOCKER_IMAGE=false

while (($#)); do
  case "$1" in
    -VersionCode)
      (($# >= 2)) || fail "Thiếu giá trị cho -VersionCode."
      VERSION_CODE=$2
      shift 2
      ;;
    -VersionName)
      (($# >= 2)) || fail "Thiếu giá trị cho -VersionName."
      VERSION_NAME=$2
      shift 2
      ;;
    -BuildDockerImage)
      BUILD_DOCKER_IMAGE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Tham số không hợp lệ: $1"
      ;;
  esac
done

[[ "$VERSION_CODE" =~ ^[1-9][0-9]{0,9}$ ]] ||
  fail "-VersionCode phải là số nguyên dương không lớn hơn 2147483647."
(( VERSION_CODE <= 2147483647 )) ||
  fail "-VersionCode phải là số nguyên dương không lớn hơn 2147483647."
[[ -n "$VERSION_NAME" ]] || fail "Cần chỉ định -VersionName."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
DOCKER_IMAGE=qfield_and_dev
BUILD_VOLUME=qfield-build-arm64
GRADLE_VOLUME=qfield-gradle-cache
KEYSTORE_PROPERTIES="$REPO_ROOT/platform/android/keystore.properties"
KEYSTORE="$REPO_ROOT/platform/android/keystores/qfield-dev.keystore"
UNSIGNED_APK="$REPO_ROOT/artifacts/android-build-release-custom-unsigned.apk"
SIGNED_APK="$REPO_ROOT/artifacts/android-build-release-custom-v${VERSION_CODE}.apk"

command -v docker >/dev/null 2>&1 || fail "Không tìm thấy Docker."
docker info >/dev/null 2>&1 || fail "Không kết nối được Docker daemon."
[[ -f "$KEYSTORE_PROPERTIES" ]] ||
  fail "Không tìm thấy platform/android/keystore.properties."
[[ -f "$KEYSTORE" ]] ||
  fail "Không tìm thấy platform/android/keystores/qfield-dev.keystore."
[[ "$REPO_ROOT" != *,* ]] ||
  fail "Đường dẫn repository không được chứa dấu phẩy để Docker --mount xử lý an toàn."

read_property() {
  local property_name=$1
  awk -F= -v wanted="$property_name" '
    /^[[:space:]]*[#!]/ { next }
    index($0, "=") {
      key = substr($0, 1, index($0, "=") - 1)
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key == wanted) {
        print value
        exit
      }
    }
  ' "$KEYSTORE_PROPERTIES"
}

for property_name in storePassword keyPassword keyAlias; do
  [[ -n "$(read_property "$property_name")" ]] ||
    fail "Thiếu hoặc chưa đặt $property_name trong keystore.properties."
done
KEY_ALIAS="$(read_property keyAlias)"

mkdir -p "$REPO_ROOT/artifacts"

if $BUILD_DOCKER_IMAGE || ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
  printf '[1/5] Build Docker image %s...\n' "$DOCKER_IMAGE"
  docker build "$REPO_ROOT/.docker/android_dev" -t "$DOCKER_IMAGE"
else
  printf '[1/5] Dùng Docker image có sẵn: %s\n' "$DOCKER_IMAGE"
fi

docker volume inspect "$BUILD_VOLUME" >/dev/null 2>&1 ||
  docker volume create "$BUILD_VOLUME" >/dev/null
docker volume inspect "$GRADLE_VOLUME" >/dev/null 2>&1 ||
  docker volume create "$GRADLE_VOLUME" >/dev/null

run_build_container() {
  docker run --rm \
    -e "APK_VERSION_CODE=$VERSION_CODE" \
    -e "APP_VERSION_STR=$VERSION_NAME" \
    --mount "type=bind,source=$REPO_ROOT,target=/usr/src/qfield" \
    -v "$BUILD_VOLUME:/usr/src/build" \
    -v "$GRADLE_VOLUME:/root/.gradle" \
    "$DOCKER_IMAGE" bash -lc "$1"
}

printf '[2/5] Configure và compile source...\n'
run_build_container '
  set -e
  cmake -S /usr/src/qfield -B /usr/src/build -G Ninja \
    -DAPP_PACKAGE_NAME=qfield \
    -DCMAKE_BUILD_TYPE=Release \
    -DANDROID_SDK_ROOT=/android-sdk \
    -DVCPKG_TARGET_TRIPLET=arm64-android \
    -DWITH_SPIX=OFF \
    -DWITH_ALL_FILES_ACCESS=OFF \
    -DAPK_VERSION_CODE="$APK_VERSION_CODE" \
    -DAPP_VERSION_STR="$APP_VERSION_STR"
  cmake --build /usr/src/build --target qfield -j2
'

printf '[3/5] Đóng gói APK release unsigned...\n'
run_build_container '
  set -e
  rm -rf /usr/src/build/src/app/android-build
  mkdir -p /usr/src/build/src/app/android-build/libs/arm64-v8a
  cp /usr/src/build/android-build/lib/libqfield_arm64-v8a.so \
    /usr/src/build/src/app/android-build/libs/arm64-v8a/
  /usr/src/build/vcpkg_installed/x64-linux/tools/Qt6/bin/androiddeployqt \
    --input /usr/src/build/src/app/android-qfield-deployment-settings.json \
    --output /usr/src/build/src/app/android-build \
    --deployment bundled --android-platform android-36 \
    --copy-dependencies-only
  find /usr/src/build/src/app/android-build/libs/arm64-v8a \
    -type f -name "*.so" \
    -exec "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
    --strip-debug {} +
  /usr/src/build/vcpkg_installed/x64-linux/tools/Qt6/bin/androiddeployqt \
    --input /usr/src/build/src/app/android-qfield-deployment-settings.json \
    --output /usr/src/build/src/app/android-build \
    --deployment bundled --android-platform android-36 --gradle --release
  unsigned_apk=/usr/src/build/src/app/android-build/build/outputs/apk/release/android-build-release-unsigned.apk
  test -f "$unsigned_apk"
  cp "$unsigned_apk" /usr/src/qfield/artifacts/android-build-release-custom-unsigned.apk
'

[[ -t 0 && -t 1 ]] ||
  fail "Ký APK cần terminal tương tác để nhập mật khẩu keystore."

printf '[4/5] Ký APK bằng keystore custom...\n'
docker run --rm -it \
  -e "APK_VERSION_CODE=$VERSION_CODE" \
  -e "KEY_ALIAS=$KEY_ALIAS" \
  --mount "type=bind,source=$REPO_ROOT,target=/usr/src/qfield" \
  "$DOCKER_IMAGE" bash -lc '
    set -e
    /android-sdk/build-tools/35.0.1/apksigner sign \
      --ks /usr/src/qfield/platform/android/keystores/qfield-dev.keystore \
      --ks-key-alias "$KEY_ALIAS" \
      --out "/usr/src/qfield/artifacts/android-build-release-custom-v$APK_VERSION_CODE.apk" \
      /usr/src/qfield/artifacts/android-build-release-custom-unsigned.apk
  '

printf '[5/5] Kiểm tra chữ ký APK...\n'
docker run --rm \
  -e "APK_VERSION_CODE=$VERSION_CODE" \
  --mount "type=bind,source=$REPO_ROOT,target=/usr/src/qfield" \
  "$DOCKER_IMAGE" bash -lc '
    set -e
    apk="/usr/src/qfield/artifacts/android-build-release-custom-v$APK_VERSION_CODE.apk"
    /android-sdk/build-tools/35.0.1/apksigner verify --verbose --print-certs "$apk"
    unzip -t "$apk" >/dev/null
    /android-sdk/build-tools/35.0.1/aapt dump badging "$apk" |
      grep -F "package: name='\''ch.opengis.qfield'\''" >/dev/null || {
      printf "APK is not the expected ch.opengis.qfield package.\n" >&2
      exit 1
    }
    unzip -Z1 "$apk" |
      grep -Fx "lib/arm64-v8a/libqfield_arm64-v8a.so" >/dev/null || {
      printf "APK is missing the QField arm64 native library.\n" >&2
      exit 1
    }
    abis=$(unzip -Z1 "$apk" |
      sed -n "s|^lib/\([^/]*\)/.*|\1|p" | sort -u)
    [[ "$abis" == "arm64-v8a" ]] || {
      printf "Unexpected native ABIs in APK: %s\n" "$abis" >&2
      exit 1
    }
  '

APK_SIZE_BYTES="$(stat -c '%s' "$SIGNED_APK")"
printf 'Build thành công: %s\n' "$SIGNED_APK"
printf 'Dung lượng APK đã ký: %s MB (%s MiB)\n' \
  "$(( APK_SIZE_BYTES / 1000000 ))" "$(( APK_SIZE_BYTES / 1048576 ))"
if (( APK_SIZE_BYTES > 500000000 )); then
  printf 'Cảnh báo: APK lớn hơn 500 MB; dung lượng này bất thường, hãy kiểm tra lại nội dung APK.\n' >&2
fi
printf 'APK unsigned: %s\n' "$UNSIGNED_APK"
printf 'Copy hoặc upload APK cần được thực hiện thủ công.\n'
