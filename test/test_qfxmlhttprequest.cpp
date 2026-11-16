#define QFIELDTEST_MAIN
#include "catch2.h"
#include "qfxmlhttprequest.h"

#include <QByteArray>
#include <QEventLoop>
#include <QFile>
#include <QHostAddress>
#include <QPointer>
#include <QRegularExpression>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <qgsproject.h>

namespace
{
  bool decodeChunkedBody( const QByteArray &encodedBody, QByteArray &decodedBody )
  {
    int offset = 0;
    while ( true )
    {
      const int lineEnd = encodedBody.indexOf( "\r\n", offset );
      if ( lineEnd < 0 )
      {
        return false;
      }

      QByteArray chunkSizeText = encodedBody.mid( offset, lineEnd - offset );
      const int extensionIndex = chunkSizeText.indexOf( ';' );
      if ( extensionIndex >= 0 )
      {
        chunkSizeText.truncate( extensionIndex );
      }

      bool sizeIsValid = false;
      const uint chunkSize = chunkSizeText.trimmed().toUInt( &sizeIsValid, 16 );
      if ( !sizeIsValid )
      {
        return false;
      }

      offset = lineEnd + 2;
      if ( chunkSize == 0 )
      {
        return encodedBody.mid( offset, 2 ) == "\r\n";
      }

      const int remainingBytes = encodedBody.size() - offset;
      if ( remainingBytes < 2 || chunkSize > static_cast<uint>( remainingBytes - 2 ) )
      {
        return false;
      }

      const int decodedChunkSize = static_cast<int>( chunkSize );
      if ( encodedBody.mid( offset + decodedChunkSize, 2 ) != "\r\n" )
      {
        return false;
      }

      decodedBody.append( encodedBody.mid( offset, decodedChunkSize ) );
      offset += decodedChunkSize + 2;
    }
  }

  bool extractHttpBody( const QByteArray &request, QByteArray &body )
  {
    body.clear();
    const int headerEnd = request.indexOf( "\r\n\r\n" );
    if ( headerEnd < 0 )
    {
      return false;
    }

    const QByteArray headers = request.left( headerEnd );
    const QByteArray encodedBody = request.mid( headerEnd + 4 );
    if ( headers.toLower().contains( "transfer-encoding: chunked" ) )
    {
      return decodeChunkedBody( encodedBody, body );
    }

    const QRegularExpression contentLengthPattern(
      QStringLiteral( "Content-Length:\\s*(\\d+)" ),
      QRegularExpression::CaseInsensitiveOption );
    const QRegularExpressionMatch contentLengthMatch = contentLengthPattern.match( QString::fromLatin1( headers ) );
    if ( !contentLengthMatch.hasMatch() )
    {
      return false;
    }

    bool lengthIsValid = false;
    const int contentLength = contentLengthMatch.captured( 1 ).toInt( &lengthIsValid );
    if ( !lengthIsValid || encodedBody.size() < contentLength )
    {
      return false;
    }

    body = encodedBody.left( contentLength );
    return true;
  }
} // namespace

TEST_CASE( "QfXmlHttpRequest writes multipart text fields before file parts" )
{
  QTemporaryDir temporaryDirectory;
  REQUIRE( temporaryDirectory.isValid() );

  QFile projectFile( temporaryDirectory.filePath( QStringLiteral( "project.qgs" ) ) );
  REQUIRE( projectFile.open( QIODevice::WriteOnly ) );
  REQUIRE( projectFile.write( "<qgis/>" ) == 7 );
  projectFile.close();

  QFile attachmentFile( temporaryDirectory.filePath( QStringLiteral( "photo.jpg" ) ) );
  REQUIRE( attachmentFile.open( QIODevice::WriteOnly ) );
  const QByteArray attachmentContents = "qfield-attachment-test-payload";
  REQUIRE( attachmentFile.write( attachmentContents ) == attachmentContents.size() );
  attachmentFile.close();

  QgsProject *project = QgsProject::instance();
  const QString originalProjectFile = project->fileName();

  QTcpServer server;
  REQUIRE( server.listen( QHostAddress::LocalHost ) );
  project->setFileName( projectFile.fileName() );

  QByteArray requestBytes;
  QByteArray multipartBody;
  bool requestCaptured = false;
  QEventLoop eventLoop;
  QObject::connect( &server, &QTcpServer::newConnection, &server, [&]() {
    QTcpSocket *socket = server.nextPendingConnection();
    QObject::connect( socket, &QTcpSocket::readyRead, &server, [&, socket]() {
      requestBytes.append( socket->readAll() );
      if ( requestCaptured || !extractHttpBody( requestBytes, multipartBody ) )
      {
        return;
      }

      requestCaptured = true;
      const QByteArray response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}";
      socket->write( response );
      socket->disconnectFromHost();
    } );
  } );

  QPointer<QfXmlHttpRequest> request( new QfXmlHttpRequest );
  int responseStatus = 0;
  QObject::connect( request.data(), &QfXmlHttpRequest::responseChanged, &eventLoop, [&]() {
    if ( request && request->readyState() == QfXmlHttpRequest::Done )
    {
      responseStatus = request->status();
      eventLoop.quit();
    }
  } );
  QTimer::singleShot( 10000, &eventLoop, &QEventLoop::quit );

  QVariantMap formFields;
  formFields.insert( QStringLiteral( "f" ), QStringLiteral( "json" ) );
  formFields.insert( QStringLiteral( "token" ), QStringLiteral( "test-token" ) );
  formFields.insert( QStringLiteral( "attachment" ), QUrl::fromLocalFile( attachmentFile.fileName() ).toString() );

  const QUrl requestUrl( QStringLiteral( "http://127.0.0.1:%1/addAttachment" ).arg( server.serverPort() ) );
  request->open( QStringLiteral( "POST" ), requestUrl );
  request->send( formFields );
  eventLoop.exec();

  if ( request && request->readyState() != QfXmlHttpRequest::Done )
  {
    request->abort();
  }
  project->setFileName( originalProjectFile );

  REQUIRE( requestCaptured );
  REQUIRE( responseStatus == 200 );
  REQUIRE( multipartBody.contains( "filename=\"photo.jpg\"" ) );
  REQUIRE( multipartBody.contains( attachmentContents ) );

  const int formatFieldPosition = multipartBody.indexOf( "name=\"f\"" );
  const int tokenFieldPosition = multipartBody.indexOf( "name=\"token\"" );
  const int attachmentFieldPosition = multipartBody.indexOf( "name=\"attachment\"" );
  REQUIRE( formatFieldPosition >= 0 );
  REQUIRE( tokenFieldPosition > formatFieldPosition );
  REQUIRE( attachmentFieldPosition > tokenFieldPosition );
}
