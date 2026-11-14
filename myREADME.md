Dưới đây là bản tổng hợp trọn gói từ lúc thiết lập ban đầu cho đến quy trình làm việc hằng ngày, cập nhật bản vá và nâng cấp phiên bản lớn (4_4) trong tương lai. Bạn có thể lưu lại để dùng làm tài liệu tra cứu nhanh bất cứ lúc nào.

Sơ đồ luồng code của bạn

• upstream (QField gốc): Chứa master, release-4_3, và sau này là release-4_4.
• origin (GitHub của bạn) & local (Máy tính):
	• master: Lưu bản gốc mới nhất của QField (chỉ để tham khảo).
	• 4_3: Bản sao sạch từ upstream/release-4_3.
	• dev: Nhánh lập trình chính của bạn (tách từ 4_3, chứa các tính năng custom).
	• release: Nhánh đóng gói sản phẩm (tách từ dev, dùng để build file cài đặt).

Phần 1: Các bước thiết lập từ đầu (Để lưu trữ hoặc cài trên máy mới)

Nếu sau này bạn đổi máy tính hoặc cần thiết lập lại từ con số 0, bạn chỉ cần chạy bộ lệnh chuẩn này:
bash
# 1. Clone repo từ GitHub cá nhân về máy (kèm đầy đủ thư viện con)
git clone --recursive https://github.com<Ten_Tai_Khoan_Cua_Ban>/QField.git
cd QField

# 2. Gắn đường dẫn QField gốc làm upstream
git remote add upstream https://github.comopengisch/QField.git
git fetch upstream

# 3. Tạo nhánh 4_3 bám theo bản ổn định của QField gốc
git checkout -b 4_3 upstream/release-4_3
git push -u origin 4_3

# 4. Tạo nhánh dev từ 4_3 để bắt đầu viết tính năng custom
git checkout -b dev
git push -u origin dev

# 5. Tạo nhánh release từ dev để sẵn sàng xuất bản build
git checkout -b release
git push -u origin release
Hãy thận trọng khi sử dụng mã.

Phần 2: Quy trình làm việc hằng ngày (Chỉ thao tác trên dev)

Mỗi ngày mở máy lên lập trình, bạn chỉ cần làm việc duy nhất trên nhánh dev:
bash
# 1. Đảm bảo đang đứng đúng nhánh dev
git checkout dev

# 2. Viết code, chỉnh sửa giao diện, thêm tính năng mới...

# 3. Lưu thay đổi và đẩy lên GitHub cá nhân
git add .
git commit -m "Mo ta ngan gon tinh nang vua lam"
git push origin dev
Hãy thận trọng khi sử dụng mã.
(Khi muốn đóng gói file cài đặt từ code đã ổn định ở dev, bạn gộp sang release rồi build):
bash
git checkout release
git merge dev
git push origin release
Hãy thận trọng khi sử dụng mã.

Phần 3: Khi nhánh 4_3 gốc có bản vá lỗi mới

Thỉnh thoảng, nhóm QField sẽ cập nhật thêm các bản vá lỗi nhỏ cho phiên bản 4.3 (upstream/release-4_3). Bạn kéo bản vá đó về nhánh 4_3 của mình rồi gộp vào dev:
bash
# 1. Kéo bản vá mới từ QField gốc về nhánh 4_3
git checkout 4_3
git pull upstream release-4_3
git push origin 4_3

# 2. Gộp bản vá từ 4_3 vào nhánh dev đang làm việc
git checkout dev
git merge 4_3

# 3. Cập nhật thư viện con và đẩy lên GitHub
git submodule update --init --recursive
git push origin dev
Hãy thận trọng khi sử dụng mã.

Phần 4: Khi QField ra mắt phiên bản mới 4_4 trong tương lai

Khi QField phát hành nhánh release-4_4 trên GitHub gốc và bạn muốn nâng cấp dự án của mình lên nền tảng mới này:
bash
# 1. Tải thông tin các nhánh mới từ QField gốc
git fetch upstream

# 2. Tạo nhánh 4_4 mới tại máy tính và GitHub của bạn
git checkout -b 4_4 upstream/release-4_4
git push -u origin 4_4

# 3. Chuyển về nhánh dev của bạn và gộp toàn bộ nền tảng 4_4 mới vào
git checkout dev
git merge 4_4

# 4. Cập nhật các thư viện con cho khớp với bản 4_4
git submodule update --init --recursive
Hãy thận trọng khi sử dụng mã.
• Lưu ý khi nâng cấp phiên bản lớn (4_3 lên 4_4): Ở bước git merge 4_4, khả năng cao sẽ xuất hiện một vài xung đột code (Conflict) do cấu trúc code gốc thay đổi nhiều. Bạn mở VS Code, kiểm tra các file báo đỏ để giữ lại phần code custom của mình trên nền code mới của 4_4, sau đó chạy:bash
git add .
git commit -m "Nang cap nen tang len QField 4.4"
git push origin dev
Hãy thận trọng khi sử dụng mã.
Bạn đã lưu lại quy trình này chưa? Bước tiếp theo bạn có cần hướng dẫn cách thiết lập môi trường build (biên dịch) mã nguồn QField thành file .apk (Android) hoặc .exe (Windows) trên máy của mình không?

## Có, sau lần build đầu tiên thì build lại thường nhanh hơn nhiều.

Nếu chỉ thêm API hoặc sửa C++/QML/Java:

- Không tải lại 229 dependency.
- CMake/vcpkg dùng lại dữ liệu trong `qfield-build-arm64`.
- Chỉ biên dịch lại file bị ảnh hưởng.
- Thường mất vài phút, tùy số lượng code thay đổi.

Chỉ chậm lại nếu thêm thư viện mới vào `vcpkg.json`, đổi Qt/NDK, đổi ABI hoặc xóa volume build.

Sau khi cập nhật code:

```powershell
git checkout dev
git pull origin dev
```

Sau khi muốn đóng gói bản release:

```powershell
git checkout release
git merge dev
```

Đảm bảo container build cũ đã kết thúc, sau đó chạy:

```powershell
docker run --rm --user root `
  -v D:\qfield-opensource\QField:/usr/src/qfield `
  -v qfield-build-arm64:/usr/src/build `
  qfield_and_dev bash -lc `
  "cmake -S /usr/src/qfield -B /usr/src/build -G Ninja `
  -D CMAKE_BUILD_TYPE=Release `
  -D VCPKG_TARGET_TRIPLET=arm64-android `
  -D ANDROID_NDK_VERSION=28.2.13676358 `
  -D ANDROID_SDK_ROOT=/android-sdk `
  -D ANDROID_BUILD_TOOLS_VERSION=35.0.1 `
  -D WITH_SPIX=OFF `
  -D WITH_ALL_FILES_ACCESS=OFF `
  -D APP_PACKAGE_NAME=qfield `
  -D APP_ICON=qfield_logo `
  -D APP_NAME=QField `
  -D VCPKG_INSTALL_OPTIONS='--allow-unsupported'; `
  cmake --build /usr/src/build; `
  cmake --build /usr/src/build --target bundle --config Release; `
  mkdir -p /usr/src/qfield/artifacts; `
  find /usr/src/build -type f -name '*.apk' -exec cp -v {} /usr/src/qfield/artifacts/ \; "
```

APK sẽ nằm trong:

```text
D:\qfield-opensource\QField\artifacts
```

Không xóa volume `qfield-build-arm64`; đó là phần giúp các lần build sau nhanh hơn.
