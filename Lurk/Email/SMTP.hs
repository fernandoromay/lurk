{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Lurk.Email.SMTP
    ( SmtpConfig(..)
    , Email(..)
    , EmailError(..)
    , sendEmail
    , sendEmailInsecure
    , smtpConfig
    ) where

import Control.Exception (bracket, try, throwIO, fromException, Exception, SomeException)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Network.Connection qualified as Conn
import System.Timeout (timeout)
import Lurk.Env (getEnv, getEnvInt, getEnvWithDefault)

-- | SMTP encryption mode
data SmtpEncryption = Plain | StartTls | SmtpS
    deriving (Show, Eq)

-- | Configuration for connecting to an SMTP server
data SmtpConfig = SmtpConfig
    { smtpHost       :: Text
    , smtpPort       :: Int
    , smtpUsername   :: Text
    , smtpPassword   :: Text
    , smtpFrom       :: Text
    , smtpFromName   :: Text
    , smtpEncryption :: Text
    } deriving (Show, Eq)

-- | The email payload
data Email = Email
    { emailTo      :: Text
    , emailSubject :: Text
    , emailHtml    :: Text
    } deriving (Show, Eq)

-- | Errors that can occur during SMTP transmission
data EmailError
    = SmtpConnectionError String
    | SmtpProtocolError String
    | SmtpAuthError String
    | SmtpTimeout
    deriving (Show, Eq)

instance Exception EmailError

-- | Send an email using SMTP over a TCP connection.
-- TLS certificate validation is enabled (secure default).
sendEmail :: SmtpConfig -> Email -> IO (Either EmailError ())
sendEmail = sendEmailWith False

-- | Send an email using SMTP, skipping TLS certificate validation.
-- Use only when connecting to servers with self-signed or expired certs.
sendEmailInsecure :: SmtpConfig -> Email -> IO (Either EmailError ())
sendEmailInsecure = sendEmailWith True

-- | Load SMTP configuration from environment variables.
-- Reads @SMTP_HOST@, @SMTP_PORT@, @SMTP_USER@, @SMTP_PASS@, @SMTP_ENCR@.
-- Returns 'Nothing' if any required field is missing.
smtpConfig :: Text -> Text -> IO (Maybe SmtpConfig)
smtpConfig fromEmail fromName = do
    mHost <- getEnv "SMTP_HOST"
    mPort <- getEnvInt "SMTP_PORT"
    mUser <- getEnv "SMTP_USER"
    mPass <- getEnv "SMTP_PASS"
    mEncr <- getEnvWithDefault "SMTP_ENCR" ""
    case (mHost, mPort, mUser, mPass) of
        (Just h, Just p, Just u, Just pw) ->
            pure $ Just SmtpConfig
                { smtpHost       = h
                , smtpPort       = p
                , smtpUsername   = u
                , smtpPassword   = pw
                , smtpFrom       = fromEmail
                , smtpFromName   = fromName
                , smtpEncryption = mEncr
                }
        _ -> pure Nothing

-- | Internal: core SMTP logic with cert validation toggle.
sendEmailWith :: Bool -> SmtpConfig -> Email -> IO (Either EmailError ())
sendEmailWith disableCert config email = do
    let host = T.unpack (smtpHost config)
        port = smtpPort config

    result <- timeout 30000000 $ try $ do
        ctx <- Conn.initConnectionContext
        let useTls = parseEncryption (smtpEncryption config) == SmtpS
            tlsSettings = Conn.TLSSettingsSimple
                { Conn.settingDisableCertificateValidation = disableCert
                , Conn.settingDisableSession = False
                , Conn.settingUseServerName = False
                }
            connParams = Conn.ConnectionParams
                { Conn.connectionHostname = host
                , Conn.connectionPort = fromIntegral port
                , Conn.connectionUseSecure = if useTls then Just tlsSettings else Nothing
                , Conn.connectionUseSocks = Nothing
                }

        bracket
            (Conn.connectTo ctx connParams)
            Conn.connectionClose
            (\conn -> do
                -- Read greeting banner (Code 220)
                _ <- expectCode 220 conn "greeting"

                -- EHLO
                sendSMTPLine conn "EHLO localhost"
                _ <- expectCode 250 conn "EHLO"

                -- STARTTLS if not SmtpS
                unless useTls $ do
                    sendSMTPLine conn "STARTTLS"
                    _ <- expectCode 220 conn "STARTTLS"
                    Conn.connectionSetSecure ctx conn tlsSettings

                    -- Second EHLO after TLS
                    sendSMTPLine conn "EHLO localhost"
                    _ <- expectCode 250 conn "EHLO after TLS"
                    pure ()

                -- AUTH LOGIN
                sendSMTPLine conn "AUTH LOGIN"
                _ <- expectCode 334 conn "AUTH LOGIN challenge 1"

                -- Username
                sendSMTPLine conn (base64EncodeBS (TE.encodeUtf8 (smtpUsername config)))
                _ <- expectCode 334 conn "AUTH LOGIN challenge 2"

                -- Password
                sendSMTPLine conn (base64EncodeBS (TE.encodeUtf8 (smtpPassword config)))
                _ <- expectCode 235 conn "AUTH LOGIN password"

                -- MAIL FROM
                sendSMTPLine conn ("MAIL FROM:<" <> TE.encodeUtf8 (smtpFrom config) <> ">")
                _ <- expectCode 250 conn "MAIL FROM"

                -- RCPT TO
                sendSMTPLine conn ("RCPT TO:<" <> TE.encodeUtf8 (emailTo email) <> ">")
                _ <- expectCode 250 conn "RCPT TO"

                -- DATA
                sendSMTPLine conn "DATA"
                _ <- expectCode 354 conn "DATA"

                -- Send the actual payload
                let payload = "From: " <> TE.encodeUtf8 (smtpFromName config <> " <" <> smtpFrom config <> ">")
                           <> "\r\nTo: " <> TE.encodeUtf8 (emailTo email)
                           <> "\r\nSubject: =?UTF-8?B?" <> base64EncodeBS (TE.encodeUtf8 (emailSubject email)) <> "?="
                           <> "\r\nMIME-Version: 1.0"
                           <> "\r\nContent-Type: text/html; charset=UTF-8"
                           <> "\r\nContent-Transfer-Encoding: base64"
                           <> "\r\n\r\n" <> base64EncodeBS (TE.encodeUtf8 (emailHtml email))
                           <> "\r\n.\r\n"
                sendSMTPLine conn payload
                _ <- expectCode 250 conn "DATA body"

                sendSMTPLine conn "QUIT"
                pure ()
            )
    case result of
        Nothing -> pure (Left SmtpTimeout)
        Just (Left e) -> pure (Left $ case fromException e of
            Just emailErr -> emailErr
            Nothing -> SmtpConnectionError (show e))
        Just (Right _) -> pure (Right ())

-- | Parse encryption mode (case-insensitive). Defaults to 'StartTls'.
parseEncryption :: Text -> SmtpEncryption
parseEncryption val = case T.toLower val of
    "plain"    -> Plain
    "starttls" -> StartTls
    "smtps"    -> SmtpS
    _          -> StartTls

----------------------------------------------------------------------
-- INTERNAL HELPERS
----------------------------------------------------------------------

sendSMTPLine :: Conn.Connection -> BS.ByteString -> IO ()
sendSMTPLine conn bs = Conn.connectionPut conn (BS.append bs "\r\n")

-- | Read a full multi-line SMTP response and verify the starting 3-digit code.
expectCode :: Int -> Conn.Connection -> String -> IO BS.ByteString
expectCode expected conn stepName = do
    fullResp <- recvContinuation conn
    let codeStr = BS.take 3 fullResp
    let codeText = TE.decodeUtf8 codeStr
    let expectedText = T.pack (show expected)
    if codeText == expectedText
        then pure fullResp
        else throwIO $ SmtpProtocolError $ "Protocol error at " ++ stepName ++ ". Expected " ++ show expected ++ ", got: " ++ T.unpack (TE.decodeUtf8 fullResp)

-- | Read multi-line response (e.g. 250-first line\r\n250-second line\r\n250 last line)
recvContinuation :: Conn.Connection -> IO BS.ByteString
recvContinuation conn = do
    chunk <- Conn.connectionGetLine 4096 conn
    if BS.length chunk > 3 && BS.index chunk 3 == 45 -- '-' means continuation
        then do
            rest <- recvContinuation conn
            pure $ BS.append chunk (BS.append "\r\n" rest)
        else pure chunk

-- | Base64 encode a ByteString (UTF-8 safe)
base64EncodeBS :: BS.ByteString -> BS.ByteString
base64EncodeBS bs
    | BS.null bs = BS.empty
    | otherwise =
        let (chunk, rest) = BS.splitAt 3 bs
            len = BS.length chunk
            b1 = fromIntegral (BS.index chunk 0) :: Int
            b2 = if len > 1 then fromIntegral (BS.index chunk 1) :: Int else 0
            b3 = if len > 2 then fromIntegral (BS.index chunk 2) :: Int else 0
            chars = [ encodeByte (b1 `div` 4)
                    , encodeByte ((b1 `mod` 4) * 16 + b2 `div` 16)
                    , encodeByte ((b2 `mod` 16) * 4 + b3 `div` 64)
                    , encodeByte (b3 `mod` 64)
                    ]
            takeLen = (len * 4 + 2) `div` 3
            pad = replicate (4 - takeLen) (61 :: Word8)  -- '='
        in BS.pack (take takeLen chars ++ pad) <> base64EncodeBS rest
  where
    encodeByte :: Int -> Word8
    encodeByte n
        | n < 26    = fromIntegral (n + 65)
        | n < 52    = fromIntegral (n + 71)
        | n < 62    = fromIntegral (n - 4)
        | n == 62   = 43  -- '+'
        | otherwise = 47  -- '/'
