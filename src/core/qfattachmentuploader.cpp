#include "qfattachmentuploader.h"

#include "qfurlutils.h"
#include "qfxmlhttprequest.h"

#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

namespace
{
  QUrl arcgisEndpoint( const QString &featureServer, int layerId, const QString &operation, qint64 objectId = -1 )
  {
    QUrl endpoint( featureServer );
    QString path = endpoint.path();
    if ( !path.endsWith( '/' ) )
      path += '/';

    path += QString::number( layerId );
    if ( objectId >= 0 )
      path += QStringLiteral( "/%1" ).arg( objectId );
    path += QStringLiteral( "/%1" ).arg( operation );
    endpoint.setPath( path );
    return endpoint;
  }
}

QfAttachmentUploader::QfAttachmentUploader( QObject *parent )
  : QObject( parent )
{
}

QObject *QfAttachmentUploader::upload( const QString &filePath,
                                       const QString &url,
                                       const QVariantMap &headers,
                                       const QVariantMap &formFields )
{
  QfXmlHttpRequest *request = new QfXmlHttpRequest( this );
  request->open( QStringLiteral( "POST" ), QUrl( url ) );

  for ( auto it = headers.constBegin(); it != headers.constEnd(); ++it )
  {
    request->setRequestHeader( it.key(), it.value().toString() );
  }

  QVariantMap multipart = formFields;
  multipart.insert( QStringLiteral( "attachment" ), QfUrlUtils::fromString( filePath ).toString() );

  // Give QML a chance to assign onload/onerror before validation/network I/O.
  QTimer::singleShot( 0, request, [request, multipart]() {
    request->send( multipart );
  } );

  return request;
}

QObject *QfAttachmentUploader::uploadArcgisAttachment( const QString &filePath,
                                                        const QString &featureServer,
                                                        int layerId,
                                                        qint64 objectId,
                                                        const QString &token )
{
  QVariantMap formFields;
  formFields.insert( QStringLiteral( "f" ), QStringLiteral( "json" ) );
  formFields.insert( QStringLiteral( "token" ), token );

  const QUrl endpoint = arcgisEndpoint( featureServer, layerId, QStringLiteral( "addAttachment" ), objectId );
  return upload( filePath, endpoint.toString(), QVariantMap(), formFields );
}

QObject *QfAttachmentUploader::queryArcgisAttachments( const QString &featureServer,
                                                        int layerId,
                                                        qint64 objectId,
                                                        const QString &token )
{
  QfXmlHttpRequest *request = new QfXmlHttpRequest( this );
  QUrl endpoint = arcgisEndpoint( featureServer, layerId, QStringLiteral( "queryAttachments" ) );

  QUrlQuery query( endpoint );
  query.addQueryItem( QStringLiteral( "objectIds" ), QString::number( objectId ) );
  query.addQueryItem( QStringLiteral( "f" ), QStringLiteral( "json" ) );
  query.addQueryItem( QStringLiteral( "token" ), token );
  endpoint.setQuery( query );

  request->open( QStringLiteral( "GET" ), endpoint );
  QTimer::singleShot( 0, request, [request]() {
    request->send();
  } );

  return request;
}
