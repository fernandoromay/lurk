{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Lurk.Html where

import Data.Text (Text)
import qualified Data.Text as T
import Data.String (IsString)
import Data.Foldable (toList)

-- | The core LURK Html type. 
-- For now, it's a wrapper around Text, but it can be expanded into a DOM tree later.
newtype Html = Html { renderHtml :: Text }
    deriving (Semigroup, Monoid, IsString)

class ToHtml a where
    toHtml :: a -> Html

instance ToHtml Text where
    toHtml = Html

instance ToHtml String where
    toHtml = Html . T.pack

instance ToHtml Html where
    toHtml = id

instance ToHtml Int where
    toHtml = toHtml . show

-- | Unsafe HTML injection (for the quasi-quoter literal parts)
preEscapedToHtml :: Text -> Html
preEscapedToHtml = Html

-- | Combine multiple HTML nodes
concatHtml :: [Html] -> Html
concatHtml = Html . T.concat . map renderHtml

-- | Map over a foldable structure and concatenate the resulting Html.
-- Synonym for @foldMap@ specialized to Html.
forEach :: Foldable t => t a -> (a -> Html) -> Html
forEach = flip foldMap

-- | Like 'forEach', but the function also receives the element's 1-based index.
forEachWithIndex :: Foldable t => t a -> (Int -> a -> Html) -> Html
forEachWithIndex xs f = foldMap (\(i, x) -> f i x) (zip [1..] (toList xs))
