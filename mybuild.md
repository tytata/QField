## Lần sau sau khi sửa code, mở PowerShell tại thư mục QField:

```powershell
cd D:\qfield-opensource\QField
```

Chạy build release đã ký:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 3 `
  -VersionName "1.0.2 - Custom"
```

Trong đó:

- `VersionCode` phải tăng thủ công: `2` → `3` → `4`...
- `VersionName` cũng tăng thủ công theo phiên bản mong muốn.
- Không cần tải lại dependency; Docker volume và Gradle cache sẽ được dùng lại.
- APK tạo tại:

```text
artifacts\android-build-release-custom-v3.apk
```

Script nằm ở `build-custom-release.ps1`.

Chỉ dùng tùy chọn `-BuildDockerImage` khi Docker image chưa tồn tại hoặc Dockerfile đã thay đổi:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 3 `
  -VersionName "1.0.2 - Custom" `
  -BuildDockerImage
```

Quy trình ngắn gọn:

```powershell
git pull
# sửa code
git add .
git commit -m "Update custom feature"
git push origin dev

.\scripts\build-custom-release.ps1 -VersionCode 3 -VersionName "1.0.2 - Custom"
```

Không sửa lại `CMakeLists.txt` để tăng version nếu đã truyền `-VersionCode` và `-VersionName`; script sẽ truyền version vào CMake khi build.



## `build-custom-release.ps1`7

Script tự động:

1. Kiểm tra Docker image và volume.
2. Configure CMake.
3. Build source.
4. Đóng gói APK release.
5. Ký bằng keystore custom.
6. Verify chữ ký APK.

Lần sau chỉ cần chạy:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\scripts\build-custom-release.ps1 `
  -VersionCode 2 `
  -VersionName "1.0.1 - Custom"
```

Bản kế tiếp tăng `VersionCode`:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 3 `
  -VersionName "1.0.2 - Custom"
```

APK kết quả nằm trong thư mục `artifacts/`, ví dụ:

`android-build-release-custom-v2.apk`

Nếu máy khác chưa có Docker image:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 2 `
  -VersionName "1.0.1 - Custom" `
  -BuildDockerImage
```

Lưu ý:

- `VersionCode` phải tăng thủ công: `1 → 2 → 3`.
- `VersionName` cũng truyền thủ công.
- Dependency và Gradle cache được tự động tái sử dụng qua Docker volume.
- Keystore và `keystore.properties` phải được copy riêng sang máy khác.
- Không commit keystore vào Git.
- Script cần được commit lên Git cùng source. Hiện `CMakeLists.txt` cũng đang có thay đổi version local; khi dùng script, version truyền bằng tham số sẽ được ưu tiên.


================
## quy trình và chạy thủ công
Dưới đây là quy trình đầy đủ cho trường hợp:

- Đã sửa code trên `dev`.
- Đã merge code vào `release`.
- Muốn build APK release.
- APK được ký bằng keystore custom hiện tại.
- Package vẫn là `ch.opengis.qfield`.

## 1. Cập nhật nhánh release

Nếu đã merge rồi, vẫn nên kiểm tra:

```powershell
git checkout release
git pull origin release
git status
```

Nếu chưa merge:

```powershell
git merge origin/dev
git push origin release
```

Từ bước này trở đi, build phải thực hiện trên nhánh `release`.

## 2. Tăng version

Hiện tại version local chưa tự tăng.

Cần tăng thủ công hai giá trị:

| Giá trị | Ý nghĩa | Ví dụ |
|---|---|---|
| `APK_VERSION_CODE` | Số dùng để Android nhận diện bản cập nhật | `1 → 2 → 3` |
| `APP_VERSION_STR` | Tên version hiển thị cho người dùng | `1.0.0 - Custom` |

Các giá trị này được khai báo trong `CMakeLists.txt` và Android Manifest sử dụng chúng tại `AndroidManifest.xml.in`.

Ví dụ:

```powershell
$VersionCode = 2
$VersionName = "1.0.0 - Custom"
```

Lần release tiếp theo:

```powershell
$VersionCode = 3
$VersionName = "1.0.1 - Custom"
```

Không được dùng lại `APK_VERSION_CODE` cũ nếu muốn cài đè bản trước.

Lưu ý: `build-vcpkg.sh` hiện đang cố định `APK_VERSION_CODE=1`, vì vậy không dùng script này trực tiếp cho release nếu chưa sửa. Ta dùng lệnh CMake bên dưới để truyền version thủ công.

## 3. Build code

Chạy trên PowerShell tại thư mục project:

```powershell
docker run --rm `
  -v "${PWD}:/usr/src/qfield" `
  -v qfield-build-arm64:/usr/src/build `
  -v qfield-gradle-cache:/root/.gradle `
  qfield_and_dev `
  bash -lc "cmake -S /usr/src/qfield -B /usr/src/build -G Ninja -DAPP_PACKAGE_NAME=qfield -DCMAKE_BUILD_TYPE=Release -DVCPKG_TARGET_TRIPLET=arm64-android -DWITH_SPIX=OFF -DWITH_ALL_FILES_ACCESS=OFF -DAPK_VERSION_CODE=$VersionCode -DAPP_VERSION_STR='$VersionName' && cmake --build /usr/src/build --target qfield -j2"
```

Ở bước này:

- Docker image được dùng lại tự động.
- Dependency trong volume `qfield-build-arm64` được dùng lại tự động.
- Code C++/QML thay đổi sẽ được build incremental.
- `APK_VERSION_CODE` và `APP_VERSION_STR` là phần truyền thủ công.
- Nếu `vcpkg.json` thay đổi, vcpkg sẽ kiểm tra và cài thêm dependency cần thiết.

## 4. Đóng gói APK release unsigned

Hiện CPack của project đang có vấn đề đường dẫn staging, nên dùng lệnh deploy thủ công:

```powershell
docker run --rm `
  -v "${PWD}:/usr/src/qfield" `
  -v qfield-build-arm64:/usr/src/build `
  -v qfield-gradle-cache:/root/.gradle `
  qfield_and_dev `
  bash -lc "mkdir -p /usr/src/build/src/app/android-build/libs/arm64-v8a && cp /usr/src/build/android-build/lib/libqfield_arm64-v8a.so /usr/src/build/src/app/android-build/libs/arm64-v8a/ && /usr/src/build/vcpkg_installed/x64-linux/tools/Qt6/bin/androiddeployqt --input /usr/src/build/src/app/android-qfield-deployment-settings.json --output /usr/src/build/src/app/android-build --deployment bundled --android-platform android-36 --gradle --release"
```

APK unsigned sẽ nằm ở:

```text
build/src/app/android-build/build/outputs/apk/release/android-build-release-unsigned.apk
```

Copy ra thư mục artifacts:

```powershell
New-Item -ItemType Directory -Force artifacts | Out-Null

docker run --rm `
  -v "${PWD}:/usr/src/qfield" `
  -v qfield-build-arm64:/usr/src/build `
  qfield_and_dev `
  bash -lc "cp /usr/src/build/src/app/android-build/build/outputs/apk/release/android-build-release-unsigned.apk /usr/src/qfield/artifacts/android-build-release-unsigned.apk"
```

## 5. Ký APK bằng keystore custom

Keystore hiện tại:

```text
platform/android/keystores/qfield-dev.keystore
```

Thông tin local nằm trong:

```text
platform/android/keystore.properties
```

Đọc password từ file:

```powershell
$KeystoreProps = @{}

Get-Content .\platform\android\keystore.properties | ForEach-Object {
    $Key, $Value = $_ -split '=', 2
    $KeystoreProps[$Key] = $Value
}
```

Ký APK:

```powershell
docker run --rm `
  -v "${PWD}:/usr/src/qfield" `
  -e "STOREPASS=$($KeystoreProps.storePassword)" `
  -e "KEYPASS=$($KeystoreProps.keyPassword)" `
  qfield_and_dev `
  bash -lc ' /android-sdk/build-tools/35.0.1/apksigner sign --ks /usr/src/qfield/platform/android/keystores/qfield-dev.keystore --ks-key-alias qfield-dev --ks-pass pass:$STOREPASS --key-pass pass:$KEYPASS --out /usr/src/qfield/artifacts/android-build-release-custom.apk /usr/src/qfield/artifacts/android-build-release-unsigned.apk '
```

Kiểm tra APK đã ký:

```powershell
docker run --rm `
  -v "${PWD}:/usr/src/qfield" `
  qfield_and_dev `
  bash -lc "/android-sdk/build-tools/35.0.1/apksigner verify --verbose --print-certs /usr/src/qfield/artifacts/android-build-release-custom.apk"
```

Nếu thấy:

```text
Verifies
Number of signers: 1
Signer #1 certificate DN: CN=QField Dev
```

là APK đã ký thành công.

## Cái gì tự động và cái gì thủ công?

| Công việc | Tự động? |
|---|---|
| Dùng lại Docker image | Có |
| Dùng lại dependency trong volume | Có |
| Build incremental code | Có |
| Kiểm tra/cài dependency mới | Có |
| Tăng `APK_VERSION_CODE` | Không, phải tăng thủ công |
| Đổi `APP_VERSION_STR` | Không, phải nhập thủ công |
| Ký bằng keystore | Hiện tại phải chạy lệnh ký |
| Tạo APK release | Có sau khi chạy lệnh deploy |
| Package name `ch.opengis.qfield` | Giữ cố định |
| Keystore | Phải dùng đúng keystore cũ |

## Ví dụ release tiếp theo

```powershell
git checkout release
git pull origin release

$VersionCode = 3
$VersionName = "1.0.1 - Custom"
```

Sau đó chạy lần lượt:

1. Lệnh build ở bước 3.
2. Lệnh đóng gói ở bước 4.
3. Lệnh ký ở bước 5.
4. Kiểm tra APK bằng `apksigner`.
5. Gửi file `android-build-release-custom.apk` cho thiết bị Android.

Keystore không được commit Git. Chỉ commit source và `.gitignore`. Nếu mất keystore, các bản APK sau không thể cập nhật đè lên APK cũ đã ký bằng keystore đó.