{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Lurk.Html where

import Data.Text (Text)
import qualified Data.Text as T
import Data.String (IsString)

-- | The core LURK Html type. 
-- For now, it's a wrapper around Text, but it can be expanded into a DOM tree later.
newtype Html = Html { renderHtml :: Text }
    deriving (Semigroup, Monoid, IsString)

class ToHtml a where
    toHtml :: a -> Html

instance ToHtml Text where
    -- Basic HTML escaping
    toHtml t = Html $ T.replace "<" "&lt;" $ T.replace ">" "&gt;" $ T.replace "&" "&amp;" t

instance ToHtml String where
    toHtml = toHtml . T.pack

instance ToHtml Html where
    toHtml = id

-- | Unsafe HTML injection (for the quasi-quoter literal parts)
preEscapedToHtml :: Text -> Html
preEscapedToHtml = Html

-- | Combine multiple HTML nodes
concatHtml :: [Html] -> Html
concatHtml = Html . T.concat . map renderHtml
