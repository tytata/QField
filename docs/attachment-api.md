# QField Attachment API

QField expose API này cho QML plugin thông qua context property
`QFieldAttachmentUploader`.

Implementation:

- [`qfattachmentuploader.h`](../src/core/qfattachmentuploader.h)
- [`qfattachmentuploader.cpp`](../src/core/qfattachmentuploader.cpp)
- [`qgismobileapp.cpp`](../src/app/qgismobileapp.cpp)
- [`qfxmlhttprequest.cpp`](../src/core/qfxmlhttprequest.cpp)

## Requirements

- APK phải được build từ source có `QFieldAttachmentUploader`.
- Server phải hỗ trợ ArcGIS FeatureServer attachments.
- Cần có `featureServer`, `layerId`, `objectId` và token hợp lệ.
- File upload phải là file local nằm trong vùng đường dẫn mà QField cho phép
  đọc.

## Upload attachment theo ArcGIS

### QML method

```qml
QFieldAttachmentUploader.uploadArcgisAttachment(
    filePath,
    featureServer,
    layerId,
    objectId,
    token
)
```

Parameters:

| Parameter | Type | Description |
|---|---|---|
| `filePath` | `string` | Đường dẫn file local cần upload. |
| `featureServer` | `string` | URL gốc của ArcGIS FeatureServer. |
| `layerId` | `int` | ID layer, ví dụ `7`. |
| `objectId` | `int64` | OBJECTID của feature, ví dụ `10812`. |
| `token` | `string` | ArcGIS authentication token. |

### HTTP request

```text
POST {featureServer}/{layerId}/{objectId}/addAttachment
Content-Type: multipart/form-data
```

Multipart fields được gửi theo thứ tự text fields trước, file sau:

```text
f=json
token={token}
attachment=<local file>
```

Thứ tự này quan trọng với một số endpoint ArcGIS. File được gửi với field name
`attachment` và filename lấy từ tên file local.

Nếu file không hợp lệ, không tồn tại, không mở được hoặc bị policy đường dẫn
của QField chặn, phần file không được upload thành công. Không nên coi response
HTTP thành công là bằng chứng file đã được lưu.

### Successful response

```json
{
  "addAttachmentResult": {
    "objectId": 801,
    "success": true
  }
}
```

`objectId` trong response là ID của attachment, không phải OBJECTID của feature.
Luôn kiểm tra cả HTTP status và `addAttachmentResult.success`.

## Query attachments

### QML method

```qml
QFieldAttachmentUploader.queryArcgisAttachments(
    featureServer,
    layerId,
    objectId,
    token
)
```

### HTTP request

```text
GET {featureServer}/{layerId}/queryAttachments
    ?objectIds={objectId}
    &f=json
    &token={token}
```

### Successful response

```json
{
  "attachmentGroups": [
    {
      "parentObjectId": 10812,
      "attachmentInfos": [
        {
          "id": 801,
          "name": "photo.jpg",
          "contentType": "image/jpeg",
          "size": 147191
        }
      ]
    }
  ]
}
```

`attachmentGroups: []` nghĩa là feature hiện chưa có attachment.

## Flow upload và kiểm tra

Phải chờ upload hoàn tất thành công trước khi gọi query:

```qml
function uploadAndVerify(filePath, featureServer, layerId, objectId, token) {
    var upload = QFieldAttachmentUploader.uploadArcgisAttachment(
        filePath, featureServer, layerId, objectId, token
    )

    upload.onload = function() {
        if (upload.status < 200 || upload.status >= 300) {
            console.log("Attachment upload failed:",
                        upload.status, upload.responseText)
            return
        }

        var result = JSON.parse(upload.responseText)
        if (!result.addAttachmentResult ||
            !result.addAttachmentResult.success) {
            console.log("ArcGIS rejected attachment:", upload.responseText)
            return
        }

        var check = QFieldAttachmentUploader.queryArcgisAttachments(
            featureServer, layerId, objectId, token
        )

        check.onload = function() {
            if (check.status >= 200 && check.status < 300) {
                console.log("Attachment verification:", check.responseText)
            } else {
                console.log("Attachment verification failed:",
                            check.status, check.responseText)
            }
        }
    }
}
```

`onload` được gọi cho cả HTTP response thành công và HTTP error. Luôn kiểm tra
`status`, `responseText` và nội dung JSON.

## Generic upload method

Method cấp thấp hơn:

```qml
QFieldAttachmentUploader.upload(
    filePath,
    url,
    headers,
    formFields
)
```

- `filePath`: file local được gửi dưới field name `attachment`.
- `url`: endpoint POST.
- `headers`: HTTP request headers.
- `formFields`: các multipart text fields bổ sung.

Field `attachment` do API tạo ra sẽ ghi đè field cùng tên trong `formFields`.
Với ArcGIS, nên dùng `uploadArcgisAttachment()` để endpoint và hai field `f`/
`token` được tạo đúng.

## Security and operational notes

- Không hard-code token trong plugin ZIP hoặc source repository.
- Dùng token ngắn hạn nếu có thể và rotate token đã bị lộ.
- Không log token hoặc đưa token vào thông báo lỗi cho người dùng.
- Validate file path và file type trong plugin trước khi upload.
- Kiểm tra `addAttachmentResult.success`, không chỉ kiểm tra HTTP status 200.
- Không đưa `keystore.properties` hoặc keystore vào Git.

## Reference

Request format dựa trên:

- `GIS-upload-attachment.postman_collection.json`
- ArcGIS FeatureServer `addAttachment`
- ArcGIS FeatureServer `queryAttachments`
