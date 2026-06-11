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

-- | A naive Haskell parser that handles `var` and `func arg1 arg2`
-- It splits by space and applies them as function calls.
-- More complex expressions will require a real Haskell AST parser.
parseSimpleCode :: String -> Q Exp
parseSimpleCode code = 
    case words code of
        [] -> stringE ""
        (f:args) -> foldl appE (varE (mkName f)) (map (varE . mkName) args)

-- | The LURK QuasiQuoter!
lurk :: QuasiQuoter
lurk = QuasiQuoter
    { quoteExp = parseLurkExp
    , quotePat = error "lurk QQ is not supported in patterns"
    , quoteType = error "lurk QQ is not supported in types"
    , quoteDec = error "lurk QQ is not supported in declarations"
    }
