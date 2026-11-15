#ifndef QFATTACHMENTUPLOADER_H
#define QFATTACHMENTUPLOADER_H

#include "qfield_core_export.h"

#include <QObject>
#include <QVariantMap>

class QFIELD_CORE_EXPORT QfAttachmentUploader : public QObject
{
    Q_OBJECT

  public:
    explicit QfAttachmentUploader( QObject *parent = nullptr );

    /** Uploads a local file as a multipart part named "attachment". */
    Q_INVOKABLE QObject *upload( const QString &filePath,
                                 const QString &url,
                                 const QVariantMap &headers = QVariantMap(),
                                 const QVariantMap &formFields = QVariantMap() );

    /** Uploads an attachment using the ArcGIS FeatureServer addAttachment API. */
    Q_INVOKABLE QObject *uploadArcgisAttachment( const QString &filePath,
                                                 const QString &featureServer,
                                                 int layerId,
                                                 qint64 objectId,
                                                 const QString &token );

    /** Checks attachments using the ArcGIS FeatureServer queryAttachments API. */
    Q_INVOKABLE QObject *queryArcgisAttachments( const QString &featureServer,
                                                 int layerId,
                                                 qint64 objectId,
                                                 const QString &token );
};

#endif // QFATTACHMENTUPLOADER_H
