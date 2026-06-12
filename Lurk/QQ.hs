module Lurk.QQ (lurk) where

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Text.Megaparsec
import Text.Megaparsec.Char
import Data.Void
import qualified Data.Text as T
import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Language.Haskell.Meta.Parse (parseExp)
import Data.Text (Text)

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

extractDotChain :: Exp -> Maybe [String]
extractDotChain (VarE n) = Just [nameBase n]
extractDotChain (UInfixE e1 (VarE op) e2) 
    | nameBase op == "." = do
        left <- extractDotChain e1
        right <- extractDotChain e2
        return (left ++ right)
extractDotChain _ = Nothing

applyFields :: [String] -> Exp -> Exp
applyFields fields expr = foldl (\acc field -> GetFieldE acc field) expr fields

rebalanceAndApply :: [String] -> Exp -> Exp
rebalanceAndApply fields (AppE f x) = AppE f (rebalanceAndApply fields x)
rebalanceAndApply fields x = applyFields fields x

transformExp :: Exp -> Exp
transformExp (LitE (StringL s)) = SigE (LitE (StringL s)) (ConT ''Text)
transformExp (LitE (IntegerL n)) = SigE (LitE (IntegerL n)) (ConT ''Int)
transformExp (UInfixE e1 (VarE op) e2)
    | nameBase op == "." = 
        case extractDotChain e2 of
            Just fields -> rebalanceAndApply fields (transformExp e1)
            Nothing -> UInfixE (transformExp e1) (VarE op) (transformExp e2)
transformExp (AppE e1 e2) = AppE (transformExp e1) (transformExp e2)
transformExp (InfixE me1 e me2) = InfixE (fmap transformExp me1) (transformExp e) (fmap transformExp me2)
transformExp (UInfixE e1 e2 e3) = UInfixE (transformExp e1) (transformExp e2) (transformExp e3)
transformExp (ParensE e) = ParensE (transformExp e)
transformExp (CondE e1 e2 e3) = CondE (transformExp e1) (transformExp e2) (transformExp e3)
transformExp (ListE es) = ListE (map transformExp es)
transformExp (VarE n)
    | "__implicit_" `isPrefixOf` nameBase n = ImplicitParamVarE (drop 11 (nameBase n))
transformExp e = e

parseSimpleCode :: String -> Q Exp
parseSimpleCode code = do
    let preprocessed = T.unpack $ T.replace "?" "__implicit_" $ T.pack code
    case parseExp preprocessed of
        Right exp -> return (transformExp exp)
        Left err -> fail $ "Parse error in LURK `{}` block: " ++ err ++ "\nCode: " ++ code

-- | Converts the parsed chunks into a single Template Haskell Expression.
parseLurkExp :: String -> Q Exp
parseLurkExp input = do
    let trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
    case parse parser "" (trim input) of
        Left err -> fail (errorBundlePretty err)
        Right chunks -> do
            let toExpChunk (Literal str) = 
                    appE (varE 'preEscapedToHtml) (appE (varE 'T.pack) (stringE str))
                toExpChunk (HaskellExp code) = 
                    appE (varE 'toHtml) (parseSimpleCode code)
            
            listExp <- listE (map toExpChunk chunks)
            appE (varE 'concatHtml) (return listExp)

-- | The LURK QuasiQuoter!
lurk :: QuasiQuoter
lurk = QuasiQuoter
    { quoteExp = parseLurkExp
    , quotePat = error "lurk QQ is not supported in patterns"
    , quoteType = error "lurk QQ is not supported in types"
    , quoteDec = error "lurk QQ is not supported in declarations"
    }
