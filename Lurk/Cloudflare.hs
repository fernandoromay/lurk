module Lurk.Cloudflare
    ( cfCountry
    , cfContinent
    , cfCity
    , cfRegion
    , cfTimezone
    , cfASN
    , cfBotScore
    , cfBotVerified
    ) where

import Data.CaseInsensitive qualified as CI
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.Wai qualified as Wai
import Lurk.Request (request)
import Lurk.Core (Action)

-- | Look up a Cloudflare header from the current request.
cfHeader :: Text -> Action (Maybe Text)
cfHeader name = do
    req <- request
    let headers = Wai.requestHeaders req
    pure $ TE.decodeUtf8 <$> lookup (CI.mk (TE.encodeUtf8 name)) headers

-- | Identify the user's country using the Cloudflare @CF-IPCountry@ header.
cfCountry :: Action (Maybe Text)
cfCountry = cfHeader "CF-IPCountry"

-- | Identify the user's continent using the Cloudflare @CF-Continent@ header.
cfContinent :: Action (Maybe Text)
cfContinent = cfHeader "CF-Continent"

-- | Identify the user's city using the Cloudflare @CF-City@ header.
cfCity :: Action (Maybe Text)
cfCity = cfHeader "CF-City"

-- | Identify the user's region using the Cloudflare @CF-Region@ header.
cfRegion :: Action (Maybe Text)
cfRegion = cfHeader "CF-Region"

-- | Identify the user's timezone using the Cloudflare @CF-Timezone@ header.
cfTimezone :: Action (Maybe Text)
cfTimezone = cfHeader "CF-Timezone"

-- | Identify the user's ASN using the Cloudflare @CF-ASNum@ header.
cfASN :: Action (Maybe Text)
cfASN = cfHeader "CF-ASNum"

-- | Identify the bot score using the Cloudflare @Cf-Bot-Score@ header (0-100).
cfBotScore :: Action (Maybe Text)
cfBotScore = cfHeader "Cf-Bot-Score"

-- | Identify whether the visitor is a verified bot using the Cloudflare @Cf-Bot-Verified@ header.
cfBotVerified :: Action (Maybe Bool)
cfBotVerified = do
    mVal <- cfHeader "Cf-Bot-Verified"
    pure $ case T.toLower <$> mVal of
        Just "true"  -> Just True
        Just "false" -> Just False
        _            -> Nothing
