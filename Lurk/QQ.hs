module Lurk.QQ (lurk) where

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Text.Megaparsec
import Text.Megaparsec.Char
import Data.Void
import qualified Data.Text as T

import Lurk.Html (concatHtml, preEscapedToHtml, toHtml)

type Parser = Parsec Void String

data Chunk = Literal String | HaskellExp String
    deriving Show

-- | Parse the raw template string into chunks of literal HTML and `{haskell}` expressions.
parser :: Parser [Chunk]
parser = many (try haskellExp <|> literal) <* eof
  where
    haskellExp = do
        _ <- char '{'
        code <- takeWhile1P (Just "Haskell code") (/= '}')
        _ <- char '}'
        return (HaskellExp code)
    
    literal = do
        text <- takeWhile1P (Just "Literal text") (/= '{')
        return (Literal text)

-- | Converts the parsed chunks into a single Template Haskell Expression.
parseLurkExp :: String -> Q Exp
parseLurkExp input = do
    case parse parser "" input of
        Left err -> fail (errorBundlePretty err)
        Right chunks -> do
            let toExpChunk (Literal str) = 
                    appE (varE 'preEscapedToHtml) (appE (varE 'T.pack) (stringE str))
                toExpChunk (HaskellExp code) = 
                    appE (varE 'toHtml) (parseSimpleCode code)
            
            listExp <- listE (map toExpChunk chunks)
            appE (varE 'concatHtml) (return listExp)

-- | Extracts balanced parentheses
extractParens :: String -> Int -> String -> (String, String)
extractParens [] _ acc = (reverse acc, [])
extractParens (c:cs) p acc
    | c == '(' = extractParens cs (p+1) (c:acc)
    | c == ')' = if p == 1 then (reverse acc, cs) else extractParens cs (p-1) (c:acc)
    | c == '"' = 
        let (str, rest) = break (== '"') cs
        in if null rest then extractParens rest p (reverse ("\"" ++ str) ++ acc)
           else extractParens (tail rest) p (reverse ("\"" ++ str ++ "\"") ++ acc)
    | otherwise = extractParens cs p (c:acc)

nextToken :: String -> (String, String)
nextToken "" = ("", "")
nextToken (c:cs)
    | c == '"' = 
        let (str, rest) = break (== '"') cs
        in if null rest then ("\"" ++ str, "") else ("\"" ++ str ++ "\"", tail rest)
    | c == '(' =
        let (inside, rest) = extractParens cs 1 ""
        in ("(" ++ inside ++ ")", rest)
    | otherwise = 
        let (w, rest) = span (\x -> x /= ' ' && x /= '(' && x /= '"') (c:cs)
        in (w, rest)

tokenize :: String -> [String]
tokenize [] = []
tokenize s = 
    let s' = dropWhile (== ' ') s
    in if null s' then []
       else let (tok, rest) = nextToken s'
            in tok : tokenize rest

splitByDot :: String -> [String]
splitByDot "" = []
splitByDot s = 
    let (w, rest) = break (== '.') s
    in w : if null rest then [] else splitByDot (tail rest)

parseToken :: String -> Q Exp
parseToken "" = stringE ""
parseToken s
    | head s == '"' && last s == '"' = litE (stringL (init (tail s)))
    | head s == '(' && last s == ')' = parseSimpleCode (init (tail s))
    | '.' `elem` s = 
        let parts = splitByDot s
        in foldl (\acc field -> appE (varE (mkName field)) acc) (varE (mkName (head parts))) (tail parts)
    | otherwise = varE (mkName s)

-- | A smarter Haskell parser that handles function application, parens, 
-- string literals, and translates `a.b` into `b a`.
parseSimpleCode :: String -> Q Exp
parseSimpleCode code = 
    case tokenize code of
        [] -> stringE ""
        [single] -> parseToken single
        (f:args) -> foldl appE (parseToken f) (map parseToken args)

-- | The LURK QuasiQuoter!
lurk :: QuasiQuoter
lurk = QuasiQuoter
    { quoteExp = parseLurkExp
    , quotePat = error "lurk QQ is not supported in patterns"
    , quoteType = error "lurk QQ is not supported in types"
    , quoteDec = error "lurk QQ is not supported in declarations"
    }
