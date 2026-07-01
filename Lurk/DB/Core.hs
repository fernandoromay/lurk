{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Lurk.DB.Core
    ( -- * Typeclasses
      DatabaseProvider(..)
    , FromRow(..)
    , ToRow(..)
    , FromField(..)
    , ToField(..)
      -- * SQL values
    , SqlValue(..)
      -- * Query
    , Query(..)
      -- * Combinators
    , field
      -- * Wrappers
    , Only(..)
    ) where

import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import Data.Time.Format (formatTime, defaultTimeLocale, parseTimeM, ParseTime)

-- | Backend-agnostic SQL query.
newtype Query = Query { unQuery :: Text }
    deriving (Show)

-- | A single SQL value.
data SqlValue
    = SqlNull
    | SqlInt Int
    | SqlDouble Double
    | SqlText Text
    | SqlByteString ByteString
    | SqlBool Bool
    | SqlLocalTime UTCTime
    deriving (Show)

----------------------------------------------------------------------
-- FromField / ToField
----------------------------------------------------------------------

-- | Convert a single 'SqlValue' to a Haskell type.
class FromField a where
    fromField :: SqlValue -> Either String a

-- | Convert a Haskell type to a single 'SqlValue'.
class ToField a where
    toField :: a -> SqlValue

-- SqlValue identity
instance FromField SqlValue where
    fromField v = Right v

instance ToField SqlValue where
    toField = id

-- Int
instance FromField Int where
    fromField (SqlInt n) = Right n
    fromField v = Left $ "expected SqlInt, got " ++ show v

instance ToField Int where
    toField = SqlInt

-- Int64
instance FromField Int64 where
    fromField (SqlInt n) = Right (fromIntegral n)
    fromField v = Left $ "expected SqlInt, got " ++ show v

instance ToField Int64 where
    toField = SqlInt . fromIntegral

-- Double
instance FromField Double where
    fromField (SqlDouble d) = Right d
    fromField v = Left $ "expected SqlDouble, got " ++ show v

instance ToField Double where
    toField = SqlDouble

-- Text
instance FromField Text where
    fromField (SqlText t) = Right t
    fromField v = Left $ "expected SqlText, got " ++ show v

instance ToField Text where
    toField = SqlText

-- String (via Text)
instance FromField String where
    fromField (SqlText t) = Right (T.unpack t)
    fromField v = Left $ "expected SqlText, got " ++ show v

instance ToField String where
    toField = SqlText . T.pack

-- ByteString
instance FromField ByteString where
    fromField (SqlByteString bs) = Right bs
    fromField v = Left $ "expected SqlByteString, got " ++ show v

instance ToField ByteString where
    toField = SqlByteString

-- Bool
instance FromField Bool where
    fromField (SqlBool b) = Right b
    fromField (SqlInt n) = Right (n /= 0)
    fromField v = Left $ "expected SqlBool or SqlInt, got " ++ show v

instance ToField Bool where
    toField = SqlBool

-- Maybe a (SqlNull -> Nothing, otherwise fromField)
instance FromField a => FromField (Maybe a) where
    fromField SqlNull = Right Nothing
    fromField v = case fromField v of
        Left err -> Left err
        Right x -> Right (Just x)

instance ToField a => ToField (Maybe a) where
    toField Nothing = SqlNull
    toField (Just x) = toField x

-- UTCTime (stored as ISO8601 text)
instance FromField UTCTime where
    fromField (SqlText t) =
        case parseTimeM False defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (T.unpack t) of
            Just t' -> Right t'
            Nothing -> Left $ "failed to parse UTCTime: " ++ T.unpack t
    fromField v = Left $ "expected SqlText for UTCTime, got " ++ show v

instance ToField UTCTime where
    toField = SqlText . T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

----------------------------------------------------------------------
-- Only (single-value wrapper)
----------------------------------------------------------------------

-- | Wrapper for single-column query results.
newtype Only a = Only { fromOnly :: a }
    deriving (Show, Eq, Ord)

instance FromField a => FromField (Only a) where
    fromField v = Only <$> fromField v

instance ToField a => ToField (Only a) where
    toField (Only x) = toField x

----------------------------------------------------------------------
-- FromRow / ToRow
----------------------------------------------------------------------

-- | Convert a list of 'SqlValue's to a Haskell type.
-- Used by TH-generated instances and backend adapters.
class FromRow a where
    fromRow :: [SqlValue] -> Either String a

-- | Convert a Haskell type to a list of 'SqlValue's.
-- Used by TH-generated instances and backend adapters.
class ToRow a where
    toRow :: a -> [SqlValue]

-- | Read a single field from a list of SqlValues.
-- Thread the remaining values for the next field.
field :: FromField a => [SqlValue] -> Either String (a, [SqlValue])
field [] = Left "not enough fields"
field (v:vs) = case fromField v of
    Left err -> Left err
    Right x -> Right (x, vs)

-- Unit instance (for queries with no parameters)
instance FromRow () where
    fromRow [] = Right ()
    fromRow _ = Left "expected no fields for ()"

instance ToRow () where
    toRow () = []

-- Only a (single column)
instance FromField a => FromRow (Only a) where
    fromRow [v] = case fromField v of
        Left err -> Left err
        Right x -> Right (Only x)
    fromRow xs = Left $ "expected exactly 1 field, got " ++ show (length xs)

instance ToField a => ToRow (Only a) where
    toRow (Only x) = [toField x]

-- Tuples (up to 3 fields, enough for most use cases)
instance (FromField a, FromField b) => FromRow (a, b) where
    fromRow [v1, v2] = (,) <$> fromField v1 <*> fromField v2
    fromRow xs = Left $ "expected 2 fields, got " ++ show (length xs)

instance (ToField a, ToField b) => ToRow (a, b) where
    toRow (a, b) = [toField a, toField b]

instance (FromField a, FromField b, FromField c) => FromRow (a, b, c) where
    fromRow [v1, v2, v3] = (,,) <$> fromField v1 <*> fromField v2 <*> fromField v3
    fromRow xs = Left $ "expected 3 fields, got " ++ show (length xs)

instance (ToField a, ToField b, ToField c) => ToRow (a, b, c) where
    toRow (a, b, c) = [toField a, toField b, toField c]

instance (FromField a, FromField b, FromField c, FromField d) => FromRow (a, b, c, d) where
    fromRow [v1, v2, v3, v4] = (,,,) <$> fromField v1 <*> fromField v2 <*> fromField v3 <*> fromField v4
    fromRow xs = Left $ "expected 4 fields, got " ++ show (length xs)

instance (ToField a, ToField b, ToField c, ToField d) => ToRow (a, b, c, d) where
    toRow (a, b, c, d) = [toField a, toField b, toField c, toField d]

----------------------------------------------------------------------
-- DatabaseProvider
----------------------------------------------------------------------

-- | Database provider interface.
-- Implement this for each backend (SQLite, PostgreSQL, MySQL).
class DatabaseProvider db where
    -- | Execute a query and return rows.
    query   :: (FromRow row, ToRow params) => db -> Query -> params -> IO [row]
    -- | Execute a statement and return the number of affected rows.
    execute :: ToRow params => db -> Query -> params -> IO Int64
    -- | Release all connections in the pool.
    closeProvider :: db -> IO ()
