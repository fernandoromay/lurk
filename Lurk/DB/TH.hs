-- | Template Haskell deriving for 'FromRow' and 'ToRow' instances.
-- Generates instances for Lurk.DB.Core typeclasses.
module Lurk.DB.TH
    ( deriveFromRow
    , camelToSnake
    , stripPrefix
    ) where

import Language.Haskell.TH
import Data.Char (toLower, isUpper)
import qualified Lurk.DB.Core as Core

-- | Derive 'FromRow' and 'ToRow' for a record type.
-- Convention: strip the type name as prefix, convert camelCase to snake_case.
deriveFromRow :: Name -> Q [Dec]
deriveFromRow typeName = do
    info <- reify typeName
    case info of
        TyConI (DataD _ _ _ _ [RecC _ fields] _) -> do
            let tyName = nameBase typeName
                fieldTypes = map (\(_, _, typ) -> typ) fields
            fromRowDec <- deriveFromRowInstance typeName fieldTypes
            toRowDec <- deriveToRowInstance typeName fieldTypes
            pure [fromRowDec, toRowDec]
        _ -> fail $ "deriveFromRow: " ++ nameBase typeName ++ " must be a record type with a single constructor"

-- | Generate a FromRow instance using Core.field with explicit threading.
--
-- Generates:
-- @
-- instance FromRow Post where
--     fromRow vals = do
--         (x1, r1) <- Core.field vals
--         (x2, r2) <- Core.field r1
--         (x3, _)  <- Core.field r2
--         pure (Post x1 x2 x3)
-- @
deriveFromRowInstance :: Name -> [Type] -> Q Dec
deriveFromRowInstance typeName fields = do
    let instanceType = AppT (ConT ''Core.FromRow) (ConT typeName)
        fieldCount = length fields
        varNames = map (\i -> mkName ("x" ++ show i)) [1..fieldCount]
        -- Generate: (x1, r1) <- Core.field vals
        --           (x2, r2) <- Core.field r1
        --           ...
        --           (xN, _)  <- Core.field rN-1
        bindStmts = zipWith3 mkBind varNames restNames prevNames
        mkBind vn rn pn = BindS (TupP [VarP vn, VarP rn]) (AppE (VarE 'Core.field) (VarE pn))
        restNames = map (\i -> mkName ("r" ++ show i)) [1..fieldCount]
        prevNames = mkName "vals" : init restNames
        -- pure (Constructor x1 x2 ... xN)
        pureExpr = AppE (VarE 'pure) (AppE (ConE typeName) (TupE (map (Just . VarE) varNames)))
        doBlock = DoE Nothing (bindStmts ++ [NoBindS pureExpr])
        fromRowClause = Clause [VarP (mkName "vals")] (NormalB doBlock) []
    pure $ InstanceD Nothing [] instanceType
        [ FunD 'Core.fromRow [fromRowClause]
        ]

-- | Generate a ToRow instance using Core.toField on each field.
--
-- Generates:
-- @
-- instance ToRow Post where
--     toRow (Post x1 x2 x3) = [Core.toField x1, Core.toField x2, Core.toField x3]
-- @
deriveToRowInstance :: Name -> [Type] -> Q Dec
deriveToRowInstance typeName fields = do
    let instanceType = AppT (ConT ''Core.ToRow) (ConT typeName)
        fieldNames = map (\i -> mkName ("x" ++ show i)) [1..length fields]
        -- [Core.toField x1, Core.toField x2, ...]
        listExpr = ListE (map (\fn -> AppE (VarE 'Core.toField) (VarE fn)) fieldNames)
        toRowClause = Clause [ConP typeName [] (map VarP fieldNames)] (NormalB listExpr) []
    pure $ InstanceD Nothing [] instanceType
        [ FunD 'Core.toRow [toRowClause]
        ]

-- | Convert camelCase to snake_case.
camelToSnake :: String -> String
camelToSnake [] = []
camelToSnake (c:cs)
    | isUpper c = '_' : toLower c : camelToSnake cs
    | otherwise = c : camelToSnake cs

-- | Strip a type name prefix from a field name.
stripPrefix :: String -> String -> String
stripPrefix [] field = field
stripPrefix (p:ps) (f:fs)
    | toLower p == toLower f = stripPrefix ps fs
    | otherwise = f : fs
stripPrefix _ field = field
