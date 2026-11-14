#include "qfattachmentuploader.h"

#include "qfurlutils.h"
#include "qfxmlhttprequest.h"

#include <QTimer>
#include <QUrl>

QfAttachmentUploader::QfAttachmentUploader( QObject *parent )
  : QObject( parent )
{
}

QObject *QfAttachmentUploader::upload( const QString &filePath,
                                       const QString &url,
                                       const QVariantMap &headers )
{
  QfXmlHttpRequest *request = new QfXmlHttpRequest( this );
  request->open( QStringLiteral( "POST" ), QUrl( url ) );

  for ( auto it = headers.constBegin(); it != headers.constEnd(); ++it )
  {
    request->setRequestHeader( it.key(), it.value().toString() );
  }

  QVariantMap multipart;
  multipart.insert( QStringLiteral( "attachment" ), QfUrlUtils::fromString( filePath ).toString() );

  // Give QML a chance to assign onload/onerror before validation/network I/O.
  QTimer::singleShot( 0, request, [request, multipart]() {
    request->send( multipart );
  } );

  return request;
}
