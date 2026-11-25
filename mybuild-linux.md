# Build và deploy APK custom trên Linux

Tài liệu này hướng dẫn tạo APK Android custom từ source QField trên Linux bằng
Docker, ký APK bằng keystore riêng và kiểm tra chữ ký. APK chỉ được tạo trong
thư mục local `artifacts/`; việc copy APK sang thiết bị, server hoặc GitHub
được thực hiện thủ công và không nằm trong quy trình này.

## 1. Yêu cầu

- Linux với Bash, Git và Docker đã cài đặt; Docker daemon đang chạy.
- Đủ dung lượng đĩa cho Docker image, build volume và các dependency Android.
- Hai file local:

  ```text
  platform/android/keystore.properties
  platform/android/keystores/qfield-dev.keystore
  ```

`keystore.properties` cần có các khóa `storePassword`, `keyPassword` và
`keyAlias` (hiện dùng `qfield-dev`). Các file này bị bỏ qua bởi Git; không
commit hoặc chia sẻ chúng.

## 2. Cập nhật source

Clone lần đầu:

```bash
git clone --branch dev --recurse-submodules https://github.com/tytata/QField.git
cd QField
```

Nếu source đã được clone trước đó:

```bash
git switch dev
git pull --ff-only origin dev
git submodule update --init --recursive
git status
```

Không ghi đè các thay đổi local chưa được lưu.

Copy hai file keystore vào đúng đường dẫn ở mục 1. `VersionCode` phải tăng sau
mỗi bản phát hành.

## 3. Build, ký và kiểm tra APK

Từ thư mục gốc của repository, chạy script tương tự script PowerShell trên
Windows:

```bash
./scripts/build-custom-release.sh \
  -VersionCode 7 \
  -VersionName "1.0.6 - Custom"
```

Script tự build Docker image nếu chưa có, tạo build volume/Gradle cache khi cần,
compile QField cho ABI `arm64-v8a`, đóng gói APK release, ký bằng keystore
custom và xác minh chữ ký. Nếu cần build lại Docker image, thêm
`-BuildDockerImage`:

```bash
./scripts/build-custom-release.sh \
  -VersionCode 7 \
  -VersionName "1.0.6 - Custom" \
  -BuildDockerImage
```

Khi ký, `apksigner` hỏi mật khẩu keystore trong terminal. Script không đưa mật
khẩu vào command line hoặc lưu chúng vào shell history.

APK đã ký nằm tại:

```text
artifacts/android-build-release-custom-v<VERSION_CODE>.apk
```

Đây là một APK cài đặt cho ABI `arm64-v8a`, package `ch.opengis.qfield`, gồm
QField cùng các thư viện native/Qt cần thiết được bundle. Script kiểm tra chữ
ký, package ID, thư viện native QField và ABI trước khi báo build thành công;
nó cũng in dung lượng APK. Bản Windows trước đây có dung lượng khoảng
117–118 MB; bản Linux nhỏ hơn hoặc bằng mức đó không cần cảnh báo. Chỉ khi APK
lớn hơn 500 MB script mới cảnh báo vì có thể đã đóng gói thêm nội dung bất
thường.

Docker có thể tạo file trong `artifacts/` với owner là root. Nếu cần quản lý
file bằng user hiện tại, đổi owner sau khi build:

```bash
sudo chown "$USER":"$(id -gn)" artifacts/android-build-release-custom-*.apk
```

Kiểm tra tên và kích thước các APK trước khi copy thủ công:

```bash
ls -lh artifacts/*.apk
```

Không dùng APK `*-unsigned.apk` để cài đặt hoặc phân phối.

## 4. Copy APK từ Linux sang Windows qua SSH

Phần này thực hiện **trên Windows** để tải APK từ máy Linux. Chỉ lấy APK đã ký
có version cụ thể; không dùng wildcard và không tải file
`*-unsigned.apk`.

Máy Linux cần bật Tailscale và chạy OpenSSH Server (`sshd`); tài khoản Linux
cần có quyền đọc APK. Trên Linux, kiểm tra SSH server đang chạy và lấy Tailscale
IPv4 bằng:

```bash
sudo systemctl status ssh
tailscale ip -4
```

Nếu SSH server chưa được cài trên Ubuntu/Debian:

```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

Cho phép kết nối SSH qua Tailscale theo firewall hiện có. Không cần mở SSH ra
Internet hoặc cấu hình port forwarding trên router. Windows cần có Tailscale
đang kết nối cùng tailnet và OpenSSH Client (`ssh`, `scp`). Mở PowerShell và
chuyển vào thư mục nhận APK để tránh nhầm dấu `:` trong đường dẫn Windows:

```powershell
Set-Location "$env:USERPROFILE\Downloads"
```

Thay `/home/LINUX_USER/QField` trong ví dụ bằng đường dẫn tuyệt đối thật tới
repository trên máy Linux.

### Cách 1: Dùng Tailscale IP

Trong PowerShell trên Windows, thử kết nối:

```powershell
ssh LINUX_USER@100.101.102.103
```

Thoát phiên SSH rồi tải APK đã ký:

```powershell
scp LINUX_USER@100.101.102.103:/home/LINUX_USER/QField/artifacts/android-build-release-custom-v7.apk .
```

Thay `LINUX_USER`, Tailscale IP, đường dẫn source và `v7` theo máy/version
thực tế. Dấu `.` là thư mục hiện tại trên Windows (`Downloads`).

### Cách 2: Dùng SSH alias

Trên Windows, tạo hoặc sửa file `$env:USERPROFILE\.ssh\config` (không có đuôi
`.txt`) và thêm:

```sshconfig
Host qfield-linux
  HostName 100.101.102.103
  User LINUX_USER
  Port 22
```

Thay IP và username bằng giá trị thực tế. Nếu dùng SSH private key không ở vị
trí mặc định, thêm `IdentityFile C:/Users/WIN_USER/.ssh/<ten-key>`. Trong
PowerShell trên Windows, kiểm tra alias rồi tải APK:

```powershell
ssh qfield-linux
scp qfield-linux:/home/LINUX_USER/QField/artifacts/android-build-release-custom-v7.apk .
```

Sau khi truyền xong, xác nhận file đã về Windows:

```powershell
Get-Item .\android-build-release-custom-v7.apk
```

Hai cách trên đều khởi tạo lệnh `scp` từ Windows và kéo đúng một APK đã ký từ
Linux; không cần bật OpenSSH Server trên Windows.

## 5. Cache và rebuild

- Chỉ sửa C++/QML: giữ nguyên Docker image và volume để build incremental.
- Sửa `.docker/android_dev/Dockerfile` hoặc muốn cập nhật SDK/NDK: build lại
  image bằng cách thêm `-BuildDockerImage` khi chạy script.
- Nghi ngờ build tree chứa artifact cũ: xóa riêng volume
  `qfield-build-arm64` rồi tạo lại; lần build sau sẽ compile dependencies từ
  đầu.
- APK được tạo ở `artifacts/`; không có bước tự động upload hay copy sang nơi
  khác.
