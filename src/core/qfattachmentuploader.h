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
                                 const QVariantMap &headers = QVariantMap() );
};

#endif // QFATTACHMENTUPLOADER_H
