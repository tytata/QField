# Build QField custom

## Kiểm tra native attachment preprocessing

Sau khi thay đổi `src/core/utils/qffileutils.h/.cpp`, phải build lại native QField và tạo APK mới; chỉ cập nhật ZIP plugin không đủ. Cài APK mới, chạy một attachment test và kiểm tra `arcgis_sync_debug.log` có dòng `Attachment image optimized=true` với `bytes<900000`. Nếu log ghi `Attachment image optimization API unavailable`, APK đang dùng artifact native cũ; hãy tạo build directory/volume mới hoặc clean incremental build rồi build lại.

Tài liệu này mô tả source hiện tại trên nhánh `dev`, gồm API upload attachment
và quy trình tạo APK Android custom.

## 1. Cập nhật source

Sau khi clone lần đầu:

```bash
git clone --branch dev https://github.com/tytata/QField.git
cd QField
git status
```

Những lần sau:

```bash
git switch dev
git pull --ff-only origin dev
git status
```

Không dùng `git checkout` hoặc `git reset --hard` nếu thư mục đang có thay đổi
chưa được lưu.

## 2. File local cần chuẩn bị

Các file sau không nằm trong Git và phải được copy riêng vào máy build:

```text
platform/android/keystore.properties
platform/android/keystores/qfield-dev.keystore
```

Trong [`.gitignore`](.gitignore), dòng 17 bỏ qua `local.properties`, dòng 18 bỏ
qua `keystore.properties`, và dòng 19 bỏ qua thư mục keystore. Không commit các
file này.

`keystore.properties` phải có ít nhất các khóa:

```properties
storePassword=...
keyPassword=...
keyAlias=qfield-dev
```

## 3. Build APK trên Windows

### Yêu cầu

- Git
- Docker Desktop đang chạy, nên dùng backend WSL2
- PowerShell
- `keystore.properties` và keystore custom như phần trên

Mở PowerShell tại thư mục repository:

```powershell
cd D:\qfield-opensource\QField
Set-ExecutionPolicy -Scope Process Bypass
```

Build release, ký APK và kiểm tra chữ ký bằng script:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 7 `
  -VersionName "1.0.6 - Custom"
```

`VersionCode` phải tăng sau mỗi bản phát hành. Script dùng lại Docker image,
build volume và Gradle cache nếu chúng đã tồn tại.

Nếu image chưa tồn tại, script sẽ tự build image. Sau khi thay đổi
[`.docker/android_dev/Dockerfile`](.docker/android_dev/Dockerfile), hoặc muốn ép
build lại image, dùng:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 7 `
  -VersionName "1.0.6 - Custom" `
  -BuildDockerImage
```

APK được tạo tại:

```text
artifacts/android-build-release-custom-v7.apk
```

### Android SDK đang dùng

Cấu hình hiện tại đồng bộ với `release-4_3`:

```text
compileSdkVersion / targetSdkVersion: 36
androiddeployqt --android-platform: android-36
build-tools: 35.0.1
minSdkVersion: 28
```

Dockerfile cài cả `platforms;android-35` và `platforms;android-36`. Sau khi
clone source trên máy mới, hoặc sau khi Dockerfile thay đổi, bắt buộc build lại
image:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 7 `
  -VersionName "1.0.6 - Custom" `
  -BuildDockerImage
```

Không nên kết luận APK đúng chỉ dựa vào tên `release`; hãy kiểm tra file thực tế:

```powershell
Get-Item .\artifacts\*.apk | Select-Object Name,Length,LastWriteTime
```

## 4. Build trên Linux

### 4.1. Build QField desktop Linux

Đây là build ứng dụng Linux, không tạo APK Android:

```bash
git switch dev
git pull --ff-only origin dev
chmod +x scripts/build-for-linux.sh
./scripts/build-for-linux.sh
```

Script này tạo build directory `build-x64-linux`.

### 4.2. Build APK Android custom bằng Docker

Hướng dẫn build, ký và kiểm tra APK custom trên Linux nằm trong
[`mybuild-linux.md`](mybuild-linux.md). Quy trình này tạo APK trong
`artifacts/`; copy hoặc upload APK sang nơi khác được thực hiện thủ công.

## 5. Khi nào cần build lại image hoặc xóa cache

- Chỉ sửa C++/QML: dùng lại image và volume, build incremental.
- Sửa Dockerfile, Android SDK/NDK hoặc Qt: build lại image.
- Đổi dependency trong `vcpkg.json`: nên build lại dependency cache.
- Nghi ngờ APK chứa artifact cũ: tạo volume build mới thay vì dùng lại
  `qfield-build-arm64`.

Kích thước APK có thể khác giữa hai máy nếu Docker image, Qt/NDK, vcpkg cache
hoặc trạng thái strip native libraries khác nhau. Cùng source và cùng ABI
`arm64-v8a` chưa đảm bảo byte-for-byte giống nhau nếu cache khác.

## 6. Cleanup Docker để giải phóng disk

Build QField dùng hai Docker volume:

```text
qfield-build-arm64
qfield-gradle-cache
```

Volume `qfield-build-arm64` chứa build tree, vcpkg và các thư viện đã compile;
volume `qfield-gradle-cache` chứa Gradle cache. Có thể xóa chúng, nhưng lần
build tiếp theo sẽ phải tải và compile dependency lại từ đầu.

### Kiểm tra dung lượng trước khi xóa

```powershell
docker system df -v
docker volume ls --filter name=qfield
```

### Cách an toàn: xóa riêng cache Gradle

Nếu muốn giữ lại dependency native đã compile:

```powershell
docker volume rm qfield-gradle-cache
```

Lần build sau Docker/Gradle sẽ tải lại các dependency Java cần thiết.

### Xóa toàn bộ cache build QField

Chỉ chạy khi chấp nhận build lại dependency:

```powershell
docker volume rm qfield-build-arm64 qfield-gradle-cache
```

Sau đó build lại image và volume bằng:

```powershell
.\scripts\build-custom-release.ps1 `
  -VersionCode 7 `
  -VersionName "1.0.6 - Custom" `
  -BuildDockerImage
```

Nếu volume đang được container sử dụng, dừng container trước rồi chạy lại lệnh
cleanup. Không xóa volume khi đang có build chạy.

### Dọn Docker toàn hệ thống

Chỉ dùng khi muốn xóa mọi resource không còn được Docker sử dụng:

```powershell
docker system prune
```

Lệnh trên có thể xóa stopped containers, unused networks và dangling images.
Không dùng `--volumes` nếu chưa chắc chắn, vì tùy chọn đó có thể xóa volume của
các project khác. Nếu muốn xem trước, chạy:

```powershell
docker system df -v
```

Các file trong `artifacts/`, `build-arm64-android-release/` và các file Android
local vẫn nằm trên filesystem của repository; cleanup Docker volume không xóa
chúng. Xóa các artifact cũ thủ công sau khi đã xác nhận không còn cần dùng.
