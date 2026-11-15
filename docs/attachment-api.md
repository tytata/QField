# QField Attachment API

API này được expose cho QML plugin thông qua context property
`QFieldAttachmentUploader`.

Implementation:

- `src/core/qfattachmentuploader.h`
- `src/core/qfattachmentuploader.cpp`
- `src/app/qgismobileapp.cpp`

## Requirements

- QField APK phải được build từ source có `QFieldAttachmentUploader`.
- Server phải là ArcGIS FeatureServer hỗ trợ attachments.
- Cần có `featureServer`, `layerId`, `objectId` và token hợp lệ.
- File upload phải là file local được QField cho phép đọc.

## Upload attachment

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

Multipart fields:

```text
f=json
token={token}
attachment=<local file>
```

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

## Verify attachment

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

An empty `attachmentGroups` array means that the feature currently has no
attachments.

## Recommended upload and verification flow

The upload request must finish successfully before the verification request is
started:

```qml
function uploadAndVerify(filePath, featureServer, layerId, objectId, token) {
    var upload = QFieldAttachmentUploader.uploadArcgisAttachment(
        filePath,
        featureServer,
        layerId,
        objectId,
        token
    )

    upload.onload = function() {
        if (upload.status < 200 || upload.status >= 300) {
            console.log("Attachment upload failed:", upload.status,
                        upload.responseText)
            return
        }

        var check = QFieldAttachmentUploader.queryArcgisAttachments(
            featureServer,
            layerId,
            objectId,
            token
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

`onload` is called for HTTP responses, including HTTP errors. Always inspect
`status` and `responseText`.

## Generic upload method

The lower-level method is also available:

```qml
QFieldAttachmentUploader.upload(
    filePath,
    url,
    headers,
    formFields
)
```

The file is always sent as a multipart field named `attachment`. `headers`
contains HTTP headers, while `formFields` contains additional multipart form
fields. For ArcGIS uploads, prefer `uploadArcgisAttachment()` because it sets
the endpoint and required `f`/`token` fields correctly.

## Security and operational notes

- Do not hard-code tokens in a plugin ZIP or source repository.
- Use short-lived tokens where possible and rotate tokens that were exposed.
- Do not log the token or include it in user-visible error messages.
- Validate the file path and file type in the plugin before starting upload.
- Treat HTTP status `200` alone as insufficient; inspect the ArcGIS JSON
  response and require `success: true` for the upload result.

## Reference

The request format is based on:

- `GIS-upload-attachment.postman_collection.json`
- ArcGIS FeatureServer `addAttachment`
- ArcGIS FeatureServer `queryAttachments`
