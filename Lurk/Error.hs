-- | Default error views and exception middleware.
--
-- Ships minimal, self-contained HTML for 404 and 500 errors.
-- Projects override by defining their own views and wiring them in Router.hs.
module Lurk.Error
    ( error404View
    , error500View
    , errorMiddleware
    ) where

import Control.Exception (SomeException, try)
import Data.ByteString.Lazy qualified as LB
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (status500)
import Network.Wai (Middleware, responseLBS, requestMethod, rawPathInfo)
import System.IO (hPutStrLn, stderr)

import Lurk.Html (Html(..), renderHtml)
import Lurk.QQ (lurk)

-- | Default 404 page. Hardcoded English, self-contained HTML.
-- No layout dependency, no CSS imports, no external resources.
error404View :: Html
error404View = [lurk|
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 — Page Not Found</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; background: #fafafa; color: #333; }
        .container { text-align: center; padding: 2rem; }
        h1 { font-size: 6rem; font-weight: 800; color: #ddd; line-height: 1; margin-bottom: 1rem; }
        p { font-size: 1.25rem; color: #666; margin-bottom: 2rem; }
        a { color: #0066cc; text-decoration: none; font-weight: 500; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>
        <p>The page you're looking for doesn't exist.</p>
        <a href="/">&larr; Back to Home</a>
    </div>
</body>
</html>
|]

-- | Default 500 page. Hardcoded English, self-contained HTML.
-- No dynamic content — safe to render without any context.
error500View :: Html
error500View = [lurk|
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>500 — Server Error</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; background: #fafafa; color: #333; }
        .container { text-align: center; padding: 2rem; }
        h1 { font-size: 6rem; font-weight: 800; color: #ddd; line-height: 1; margin-bottom: 1rem; }
        p { font-size: 1.25rem; color: #666; margin-bottom: 2rem; }
        a { color: #0066cc; text-decoration: none; font-weight: 500; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>500</h1>
        <p>Something went wrong. Please try again later.</p>
        <a href="/">&larr; Back to Home</a>
    </div>
</body>
</html>
|]

-- | WAI middleware that catches unhandled exceptions and renders 'error500View'.
-- Exceptions are logged to stderr. No exception details are exposed in the response.
errorMiddleware :: Middleware
errorMiddleware app req respond = do
    result <- try (app req respond)
    case result of
        Right response -> return response
        Left (ex :: SomeException) -> do
            let method = TE.decodeUtf8 (requestMethod req)
                path = TE.decodeUtf8 (rawPathInfo req)
            hPutStrLn stderr $ "ERROR " ++ T.unpack method ++ " " ++ T.unpack path ++ ": " ++ show ex
            respond $ responseLBS
                status500
                [("Content-Type", "text/html; charset=utf-8")]
                (LB.fromStrict $ TE.encodeUtf8 $ renderHtml error500View)
