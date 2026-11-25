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

Chỉ copy APK đã ký có version cụ thể, không dùng wildcard và không copy file
`*-unsigned.apk`. Chạy các lệnh sau từ thư mục gốc của repository:

```bash
APK="$(pwd -P)/artifacts/android-build-release-custom-v7.apk"
test -f "$APK"
ls -lh "$APK"
```

Máy Windows cần bật Tailscale và chạy OpenSSH Server (`sshd`); tài khoản SSH
phải có quyền ghi vào thư mục đích. Nếu chưa cài OpenSSH Server, mở PowerShell
với quyền Administrator trên Windows và chạy:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
```

Đảm bảo firewall cho phép SSH (TCP 22) qua Tailscale. Không cần mở cổng SSH ra
Internet hoặc cấu hình port forwarding trên router. Trên Windows, lấy Tailscale
IPv4 bằng `tailscale ip -4`; từ Linux, có thể kiểm tra kết nối bằng `ssh`.

### Cách 1: Dùng Tailscale IP

```bash
ssh "WIN_USER@100.101.102.103"
```

Sau khi xác nhận đăng nhập được, thoát khỏi SSH rồi copy APK:

```bash
scp "$APK" "WIN_USER@100.101.102.103:C:/Users/WIN_USER/Downloads/"
```

Thay `WIN_USER`, địa chỉ IP và thư mục `C:/Users/...` bằng tài khoản, Tailscale
IP và đường dẫn profile Windows thực tế. Dùng dấu `/` trong đường dẫn đích
Windows. Có thể kiểm tra thư mục profile bằng `$env:USERPROFILE` trong
PowerShell; tên thư mục profile không phải lúc nào cũng trùng tên đăng nhập SSH.

### Cách 2: Dùng SSH alias

Trên Linux, thêm cấu hình vào `~/.ssh/config`:

```sshconfig
Host qfield-windows
  HostName 100.101.102.103
  User WIN_USER
  Port 22
```

Thay IP và username bằng giá trị thực tế. Nếu SSH key không nằm ở vị trí mặc
định, thêm `IdentityFile ~/.ssh/<ten-key>`. Sau đó kiểm tra kết nối và copy:

```bash
ssh qfield-windows
scp "$APK" "qfield-windows:C:/Users/WIN_USER/Downloads/"
```

Hai cách trên dùng OpenSSH Server của Windows qua mạng Tailscale. Thư mục
Downloads trên Windows sẽ chỉ nhận file APK đã chọn.

## 5. Cache và rebuild

- Chỉ sửa C++/QML: giữ nguyên Docker image và volume để build incremental.
- Sửa `.docker/android_dev/Dockerfile` hoặc muốn cập nhật SDK/NDK: build lại
  image bằng cách thêm `-BuildDockerImage` khi chạy script.
- Nghi ngờ build tree chứa artifact cũ: xóa riêng volume
  `qfield-build-arm64` rồi tạo lại; lần build sau sẽ compile dependencies từ
  đầu.
- APK được tạo ở `artifacts/`; không có bước tự động upload hay copy sang nơi
  khác.
