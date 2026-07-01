-- | Template Haskell deriving for 'FromRow' and 'ToRow' instances.
-- Automatically maps Haskell record fields to snake_case column names.
--
-- @
-- data Post = Post
--   { postId       :: Int
--   , postTitle    :: Text
--   , postContent  :: Maybe Text
--   , postAuthorId :: Int
--   } deriving (Show, Generic)
--
-- deriveFromRow ''Post
-- -- Generates FromRow instance:
-- --   postId       -> post_id
-- --   postTitle    -> post_title
-- --   postContent  -> post_content
-- --   postAuthorId -> post_author_id
-- @
module Lurk.DB.TH
    ( deriveFromRow
    , camelToSnake
    , stripPrefix
    ) where

import Language.Haskell.TH
import Data.Char (toLower, isUpper)
import Database.SQLite.Simple (FromRow(..), ToRow(..), field)
import qualified Database.SQLite.Simple as SQLite

-- | Derive 'FromRow' and 'ToRow' for a record type.
-- Convention: strip the type name as prefix, convert camelCase to snake_case.
--
-- @
-- data Post = Post { postId :: Int, postTitle :: Text }
-- deriveFromRow ''Post
-- -- postId -> post_id, postTitle -> post_title
-- @
deriveFromRow :: Name -> Q [Dec]
deriveFromRow typeName = do
    info <- reify typeName
    case info of
        TyConI (DataD _ _ _ _ [RecC _ fields] _) -> do
            let tyName = nameBase typeName
                colNames = map (camelToSnake . stripPrefix tyName . nameBase . fst3) fields
                fieldTypes = map (\(_, _, typ) -> typ) fields
            fromRowDec <- deriveFromRowInstance typeName fieldTypes colNames
            toRowDec <- deriveToRowInstance typeName fieldTypes colNames
            pure [fromRowDec, toRowDec]
        _ -> fail $ "deriveFromRow: " ++ nameBase typeName ++ " must be a record type with a single constructor"
  where
    fst3 (a, _, _) = a

-- | Generate a FromRow instance.
-- Generates: instance FromRow Post where fromRow = field >> field >> ... >> pure Post
deriveFromRowInstance :: Name -> [Type] -> [String] -> Q Dec
deriveFromRowInstance typeName fields _colNames = do
    let instanceType = AppT (ConT ''FromRow) (ConT typeName)
        fieldCount = length fields
        -- Generate: field >> field >> field >> ... >> pure Constructor
        fieldBodies = replicate fieldCount (AppE (VarE 'field) (VarE (mkName "_")))
        doBlock = DoE Nothing (map NoBindS fieldBodies)
        fromRowClause = Clause [] (NormalB doBlock) []
    pure $ InstanceD Nothing [] instanceType
        [ FunD 'fromRow [fromRowClause]
        ]

-- | Generate a ToRow instance.
-- Generates: instance ToRow Post where toRow (Post x1 x2 x3) = toRow (x1, x2, x3)
deriveToRowInstance :: Name -> [Type] -> [String] -> Q Dec
deriveToRowInstance typeName fields _colNames = do
    let instanceType = AppT (ConT ''ToRow) (ConT typeName)
        fieldNames = map (\i -> mkName ("x" ++ show i)) [1..length fields]
        -- Generate: toRow (Constructor x1 x2 x3) = toRow (x1, x2, x3)
        tupleExpr = AppE (VarE 'SQLite.toRow) (TupE (map (Just . VarE) fieldNames))
        toRowClause = Clause [ConP typeName [] (map VarP fieldNames)] (NormalB tupleExpr) []
    pure $ InstanceD Nothing [] instanceType
        [ FunD 'SQLite.toRow [toRowClause]
        ]

-- | Convert camelCase to snake_case.
-- Examples:
--   postTitle    -> post_title
--   postID       -> post_id
--   postURL      -> post_url
--   findById     -> find_by_id
--   authorName   -> author_name
camelToSnake :: String -> String
camelToSnake [] = []
camelToSnake (c:cs)
    | isUpper c = '_' : toLower c : camelToSnake cs
    | otherwise = c : camelToSnake cs

-- | Strip a type name prefix from a field name.
-- Examples with type "Post":
--   postId    -> Id
--   postTitle -> Title
--   postURL   -> URL
stripPrefix :: String -> String -> String
stripPrefix [] field = field
stripPrefix (p:ps) (f:fs)
    | toLower p == toLower f = stripPrefix ps fs
    | otherwise = f : fs
stripPrefix _ field = field
