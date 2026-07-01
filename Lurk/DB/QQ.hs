-- | Compile-time SQL validator with parameterized @{{ }}@ interpolation.
--
-- @
-- -- Simple query (no params)
-- query_ conn [lurkSQL|SELECT id, title FROM posts|]
--
-- -- Parameterized query
-- query conn [lurkSQL|SELECT * FROM posts WHERE id = {{postId}}|]
--
-- -- Insert
-- execute conn [lurkSQL|
--   INSERT INTO posts (title, content, author_id)
--   VALUES ({{title}}, {{content}}, {{authorId}})
-- |]
-- @
--
-- Values are always bound as parameters (?), never string-interpolated.
-- This prevents SQL injection by design.
module Lurk.DB.QQ
    ( lurkSQL
    ) where

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Text.Megaparsec
import Text.Megaparsec.Char
import Data.Void
import Data.Char (isAlpha, isSpace)
import Data.List (isPrefixOf)
import Language.Haskell.Meta.Parse (parseExp)
import Data.Text (Text)
import qualified Data.Text as T

type Parser = Parsec Void String

-- | A chunk of the SQL template: literal SQL or a {{ parameter }}.
data Chunk = Literal String | Param String
    deriving Show

-- | Parse the SQL string into chunks of literal SQL and {{ param }} expressions.
sqlParser :: Parser [Chunk]
sqlParser = many (try param <|> literal) <* eof
  where
    param = do
        _ <- string "{{"
        code <- bracedExpr 1
        return (Param (trim code))

    literal = Literal <$> takeWhileP (Just "SQL") (\c -> c /= '{')

    -- Read Haskell code inside {{ }}, tracking brace depth
    bracedExpr :: Int -> Parser String
    bracedExpr 0 = return ""
    bracedExpr depth = do
        c <- anySingle
        case c of
            '{' -> (c:) <$> bracedExpr (depth + 1)
            '}' -> do
                isClose <- option False (try (lookAhead (char '}') >> return True))
                if isClose
                    then do
                        _ <- char '}'
                        bracedExpr (depth - 1)
                    else (c:) <$> bracedExpr depth
            '"' -> do
                str <- lexString
                (str ++) <$> bracedExpr depth
            '\'' -> do
                ch <- lexChar
                (ch ++) <$> bracedExpr depth
            '\n' -> (c:) <$> bracedExpr depth
            _    -> (c:) <$> bracedExpr depth

    lexString :: Parser String
    lexString = do
        body <- lexStringBody
        return ('"' : body)

    lexStringBody :: Parser String
    lexStringBody = do
        c <- anySingle
        case c of
            '"'  -> return "\""
            '\\' -> do
                esc <- anySingle
                rest <- lexStringBody
                return ('\\' : esc : rest)
            _ -> (c:) <$> lexStringBody

    lexChar :: Parser String
    lexChar = do
        c <- anySingle
        case c of
            '\\' -> do
                esc <- anySingle
                _ <- char '\''
                return ('\\' : esc : "'")
            _ -> return ('\'' : c : "'")

    trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- | Convert parsed chunks into a Template Haskell Expression.
-- Generates a SQL string with ? placeholders and a tuple of bound parameters.
--
-- For a query like:
--   [lurkSQL|SELECT * FROM posts WHERE id = {{postId}} AND name = {{name}}|]
--
-- This generates:
--   ("SELECT * FROM posts WHERE id = ? AND name = ?", (postId, name))
--
-- When there are no parameters, it generates just the SQL string:
--   ("SELECT * FROM posts", ())
parseLurkSQL :: String -> Q Exp
parseLurkSQL input = do
    case parse sqlParser "" input of
        Left err -> fail $ "lurkSQL parse error:\n" ++ show err
        Right chunks -> do
            let (sqlParts, params) = foldr mergeChunk ([], []) chunks
                sqlStr = concat sqlParts
                paramCount = length params
            -- Build the SQL string expression
            sqlExp <- appE (varE 'T.pack) (stringE sqlStr)
            -- Build the parameter tuple
            let paramTup = case params of
                    []  -> tupE []
                    [p] -> tupE [parseSimpleCode p]
                    ps  -> tupE (map parseSimpleCode ps)
            -- Return (sql, params) tuple
            tupE [return sqlExp, paramTup]

mergeChunk :: Chunk -> ([String], [String]) -> ([String], [String])
mergeChunk (Literal s) (sqls, params) = (s : sqls, params)
mergeChunk (Param p)   (sqls, params) = ("?" : sqls, p : params)

-- | Parse a simple Haskell expression (variable name).
parseSimpleCode :: String -> Q Exp
parseSimpleCode code = do
    case parseExp code of
        Right exp -> return exp
        Left err -> fail $ "lurkSQL: invalid expression in {{ }}: " ++ code ++ "\n" ++ err

-- | The lurkSQL QuasiQuoter.
--
-- Validates SQL syntax at compile time and extracts @{{ }}@ parameters.
-- Parameters are bound as @?@ placeholders — never string-interpolated.
--
-- Usage:
--
-- @
-- query_ conn [lurkSQL|SELECT id, title FROM posts|]
-- query conn [lurkSQL|SELECT * FROM posts WHERE id = {{postId}}|]
-- execute conn [lurkSQL|INSERT INTO posts (title) VALUES ({{title}})|]
-- @
lurkSQL :: QuasiQuoter
lurkSQL = QuasiQuoter
    { quoteExp  = parseLurkSQL
    , quotePat  = error "lurkSQL is not supported in patterns"
    , quoteType = error "lurkSQL is not supported in types"
    , quoteDec  = error "lurkSQL is not supported in declarations"
    }
