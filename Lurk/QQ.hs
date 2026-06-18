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

-- | Parse the raw template string into chunks of literal HTML and {{haskell}} expressions.
parser :: Parser [Chunk]
parser = many (try haskellExp <|> literal) <* eof
  where
    haskellExp = do
        _ <- string "{{"
        code <- bracedExpr 1
        return (HaskellExp code)

    -- | Read Haskell code inside {{ }}, tracking brace depth and lurk nesting.
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
            '[' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- bracketSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|]") ++) <$> bracedExpr depth
                    else (c:) <$> bracedExpr depth
            '(' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- lurkSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|)") ++) <$> bracedExpr depth
                    else (c:) <$> bracedExpr depth
            '\n' -> (c:) <$> bracedExpr depth
            _    -> (c:) <$> bracedExpr depth

    -- | Skip content inside (lurk|...|), tracking nested lurk depth.
    lurkSkip :: Int -> Parser String
    lurkSkip 0 = return ""
    lurkSkip n = do
        c <- anySingle
        case c of
            '|' -> do
                isClose <- option False (try (lookAhead (char ')') >> return True))
                if isClose
                    then do
                        _ <- char ')'
                        lurkSkip (n - 1)
                    else (c:) <$> lurkSkip n
            '(' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- lurkSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|)") ++) <$> lurkSkip n
                    else (c:) <$> lurkSkip n
            '[' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- bracketSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|]") ++) <$> lurkSkip n
                    else (c:) <$> lurkSkip n
            _ -> (c:) <$> lurkSkip n

    -- | Skip content inside [lurk|...|], tracking nested lurk depth.
    bracketSkip :: Int -> Parser String
    bracketSkip 0 = return ""
    bracketSkip n = do
        c <- anySingle
        case c of
            '|' -> do
                isClose <- option False (try (lookAhead (char ']') >> return True))
                if isClose
                    then do
                        _ <- char ']'
                        bracketSkip (n - 1)
                    else (c:) <$> bracketSkip n
            '[' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- bracketSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|]") ++) <$> bracketSkip n
                    else (c:) <$> bracketSkip n
            '(' -> do
                isLurk <- option False (try (lookAhead (string "lurk|") >> return True))
                if isLurk
                    then do
                        _ <- string "lurk|"
                        inner <- lurkSkip 1
                        (([c] ++ "lurk|" ++ inner ++ "|)") ++) <$> bracketSkip n
                    else (c:) <$> bracketSkip n
            _ -> (c:) <$> bracketSkip n

    literal = do
        text <- takeWhile1P (Just "Literal text") (\c -> c /= '{')
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
    let (cleanCode, lurks) = extractInnerLurks code
        preprocessed = T.unpack
          . T.replace "?" "__implicit_"
          $ T.pack cleanCode
    case parseExp preprocessed of
        Right exp -> replaceInnerLurks lurks (transformExp exp)
        Left err -> fail $ "Parse error in LURK `{{}}` block: " ++ err ++ "\nCode: " ++ code

-- | Extract (lurk|...|) blocks, replacing each with a placeholder variable.
-- Tracks nested (lurk|...) depth so inner closes don't prematurely terminate extraction.
extractInnerLurks :: String -> (String, [String])
extractInnerLurks = go 0 id
  where
    go _ acc [] = (acc [], [])
    go n acc ('(':'l':'u':'r':'k':'|':rest) =
        let (content, afterClose) = findLurkClose rest 1
            name = "__innerLurk_" ++ show n ++ "__"
            (restStr, lurks) = go (n+1) id afterClose
        in (acc (name ++ restStr), content : lurks)
    go n acc (c:rest) = go n (acc . (c:)) rest

    -- | Find the matching |) for a (lurk|...|) block, tracking nested depth.
    findLurkClose [] _ = ([], [])
    findLurkClose s 0 = (s, [])  -- shouldn't happen, but safety
    findLurkClose ('|':')':rest) 1 = ([], rest)
    findLurkClose ('|':')':rest) n = let (a, b) = findLurkClose rest (n - 1) in ('|':')':a, b)
    findLurkClose ('(':'l':'u':'r':'k':'|':rest) n =
        let (a, b) = findLurkClose rest (n + 1) in ('(':'l':'u':'r':'k':'|':a, b)
    findLurkClose (c:rest) n = let (a, b) = findLurkClose rest n in (c:a, b)

-- | Replace placeholder variables in the AST with recursively parsed lurk QQs.
replaceInnerLurks :: [String] -> Exp -> Q Exp
replaceInnerLurks [] exp = return exp
replaceInnerLurks lurks exp = do
    let names = map (\(i, _) -> mkName ("__innerLurk_" ++ show i ++ "__")) (zip [0..] lurks)
        pairs = zip names lurks
    go pairs exp
  where
    go pairs (VarE n) = case lookup n pairs of
        Just lurkBody -> parseLurkExp lurkBody
        Nothing -> return (VarE n)
    go pairs (AppE f x) = AppE <$> go pairs f <*> go pairs x
    go pairs (LamE pats body) = LamE pats <$> go pairs body
    go pairs (LetE decs body) = LetE decs <$> go pairs body
    go pairs (CaseE scrut matches) = CaseE <$> go pairs scrut <*> mapM (goMatch pairs) matches
    go pairs (TupE es) = TupE <$> mapM (mapM (go pairs)) es
    go pairs (ListE es) = ListE <$> mapM (go pairs) es
    go pairs (ParensE e) = ParensE <$> go pairs e
    go pairs (SigE e t) = flip SigE t <$> go pairs e
    go pairs (InfixE me1 e me2) = InfixE <$> traverse (go pairs) me1 <*> go pairs e <*> traverse (go pairs) me2
    go pairs (UInfixE e1 e2 e3) = UInfixE <$> go pairs e1 <*> go pairs e2 <*> go pairs e3
    go pairs (CondE c t f) = CondE <$> go pairs c <*> go pairs t <*> go pairs f
    go pairs other = return other

    goMatch pairs (Match p body decs) = Match p <$> goBody pairs body <*> return decs
    goBody pairs (GuardedB drs) = GuardedB <$> mapM (\(guard, e) -> (guard,) <$> go pairs e) drs
    goBody pairs other = return other

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
