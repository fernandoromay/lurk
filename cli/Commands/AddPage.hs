{-# LANGUAGE OverloadedStrings #-}
module Commands.AddPage
    ( addPage
    ) where

import System.Directory (doesDirectoryExist, listDirectory, createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>), takeFileName, dropExtension)
import Control.Monad (when)
import Data.List (isPrefixOf, isSuffixOf)
import Data.Char (isAlphaNum, toLower, toUpper)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Text.Encoding as TE

import Shared ( scaffoldTemplates, promptChoice, promptCustomDir, capitalize )

addPage :: String -> IO ()
addPage defaultName = do
    putStrLn "--- Adding New Page ---"
    pageNameInput <- if not (null defaultName)
        then pure defaultName
        else do
            putStrLn "Page Name (e.g., About Us):"
            putStr "> "
            getLine

    let cleanName = filter (\c -> isAlphaNum c || c == ' ' || c == '-') pageNameInput
    let wordsList = words $ map (\c -> if c == '-' then ' ' else c) cleanName
    let pascalName = concatMap capitalize wordsList
    let camelName = case wordsList of
            [] -> ""
            (w:ws) -> map toLower w ++ concatMap capitalize ws
    let kebabName = T.unpack $ T.intercalate "-" $ map (T.toLower . T.pack) wordsList

    target <- promptChoice "Where is the module located?"
        [ ("Root directory (.)", ".")
        , ("Web/ subdirectory", "Web")
        , ("Custom directory", "")
        ]
    targetDir <- case target of
        "." -> pure "."
        "" -> promptCustomDir
        custom -> pure custom

    let ctrlDir = targetDir </> "Controller"
    ctrlExists <- doesDirectoryExist ctrlDir
    ctrlFiles <- if ctrlExists
        then filter (\f -> ".hs" `isSuffixOf` f) <$> listDirectory ctrlDir
        else pure []

    targetCtrl <- if null ctrlFiles
        then do
            putStrLn $ "Warning: No controllers found in " ++ ctrlDir
            pure ""
        else do
            choice <- promptChoice "Controller to modify:" (map (\f -> (f, f)) ctrlFiles)
            pure $ ctrlDir </> choice

    let langFile = targetDir </> "Language.hs"
    langExists <- doesFileExist langFile
    langs <- if langExists
        then do
            content <- TIO.readFile langFile
            let isLangDef line = "data Language" `T.isPrefixOf` T.strip line || "data Language =" `T.isInfixOf` line
            let langLines = dropWhile (not . isLangDef) (T.lines content)
            let langBlock = takeWhile (\l -> not (T.null (T.strip l)) && not ("deriving" `T.isInfixOf` l)) langLines
            let combined = T.concat langBlock
            let afterEq = T.drop 1 $ snd $ T.breakOn "=" combined
            let stripped = T.filter (\c -> isAlphaNum c || c == '|') afterEq
            let parsedLangs = map T.unpack $ T.splitOn "|" stripped
            pure (filter (not . null) parsedLangs)
        else pure []

    let templatePrefix = "add/page/"
    let cleanPath = dropWhile (== '/')
    let templateFiles = filter (\(fp, _) -> templatePrefix `isPrefixOf` cleanPath fp) scaffoldTemplates

    let mLocaleTemplate = lookup "add/page/Locale.hs" templateFiles
    let mViewTemplate = lookup "add/page/View.hs" templateFiles

    case (mLocaleTemplate, mViewTemplate) of
        (Just localeTpl, Just viewTpl) -> do
            let replacePlaceholders text =
                    T.replace "{{PascalName}}" (T.pack pascalName) $
                    T.replace "{{camelName}}" (T.pack camelName) $
                    T.replace "{{kebab-name}}" (T.pack kebabName) text

            let langImpls = if null langs
                    then "locale = " ++ pascalName ++ "Locale { seo = commonSeo { canonical = Just $ domain <> " ++ camelName ++ "Path }, title = \"\", description = \"\" }"
                    else unlines [ "locale " ++ l ++ " = " ++ pascalName ++ "Locale\n    { seo = commonSeo { canonical = Just $ domain <> " ++ camelName ++ "Path " ++ l ++ " }\n    , title = \"\"\n    , description = \"\"\n    }" | l <- langs ]

            let localeContent = T.replace "{{language-implementations}}" (T.pack langImpls) $ replacePlaceholders (TE.decodeUtf8 localeTpl)
            let viewContent = replacePlaceholders (TE.decodeUtf8 viewTpl)

            createDirectoryIfMissing True (targetDir </> "Locale")
            createDirectoryIfMissing True (targetDir </> "View")

            TIO.writeFile (targetDir </> "Locale" </> pascalName ++ ".hs") localeContent
            putStrLn $ "Created " ++ (targetDir </> "Locale" </> pascalName ++ ".hs")

            TIO.writeFile (targetDir </> "View" </> pascalName ++ ".hs") viewContent
            putStrLn $ "Created " ++ (targetDir </> "View" </> pascalName ++ ".hs")

            -- Inject into Paths.hs
            let pathsFile = targetDir </> "Paths.hs"
            pathsExists <- doesFileExist pathsFile
            when pathsExists $ do
                pathsContent <- TIO.readFile pathsFile
                let pathsImpls = if null langs
                        then T.pack $ camelName ++ "Path :: Text\n" ++ camelName ++ "Path = \"/" ++ kebabName ++ "/\"\n"
                        else T.pack $ unlines $ (camelName ++ "Path :: Language -> Text") :
                            [ camelName ++ "Path " ++ l ++ " = \"/" ++ (if l == "EN" then "" else T.unpack (T.toLower (T.pack l)) ++ "/") ++ kebabName ++ "/\"" | l <- langs ]

                let pLines = T.lines pathsContent
                let injectPageAlts [] = []
                    injectPageAlts (l:ls)
                        | "pageAlts = langPaths [" `T.isInfixOf` l =
                            let (before, after) = T.breakOn "]" l
                                prefix = if "[" `T.isSuffixOf` T.strip before then "" else ", "
                            in (before <> prefix <> T.pack camelName <> "Path" <> after) : ls
                        | otherwise = l : injectPageAlts ls

                let updatedPaths = T.unlines (injectPageAlts pLines) <> "\n" <> pathsImpls
                TIO.writeFile pathsFile updatedPaths
                putStrLn $ "Updated " ++ pathsFile

            -- Inject into Controller
            when (not (null targetCtrl)) $ do
                ctrlContent <- TIO.readFile targetCtrl
                let cLines = T.lines ctrlContent
                let isImport l = "import " `T.isPrefixOf` T.strip l
                let (beforeImports, rest1) = span (not . isImport) cLines
                let (imports, afterImports) = span isImport rest1
                let newImports =
                        [ T.pack $ "import View." ++ pascalName
                        , T.pack $ "import Locale." ++ pascalName ++ " qualified as " ++ pascalName
                        ]

                let actionImpl = T.pack $ unlines
                        [ ""
                        , camelName ++ "Action :: (?lang :: Language) => Action ()"
                        , camelName ++ "Action = render $ " ++ camelName ++ "View (" ++ pascalName ++ ".locale ?lang)"
                        ]

                let updatedCtrl = T.unlines (beforeImports ++ imports ++ newImports ++ afterImports) <> "\n" <> actionImpl
                TIO.writeFile targetCtrl updatedCtrl
                putStrLn $ "Updated " ++ targetCtrl

            -- Inject into Router.hs
            let routerFile = targetDir </> "Router.hs"
            routerExists <- doesFileExist routerFile
            when routerExists $ do
                routerContent <- TIO.readFile routerFile
                let rLines = T.lines routerContent

                let ctrlModName = dropExtension (takeFileName targetCtrl)
                let hasCtrlImport = any (\l -> ("import Controller." <> T.pack ctrlModName) `T.isInfixOf` l) rLines
                let isImport l = "import " `T.isPrefixOf` T.strip l
                let rLinesWithImport = if hasCtrlImport || null targetCtrl
                        then rLines
                        else let (bi, r1) = span (not . isImport) rLines
                                 (ims, ai) = span isImport r1
                             in bi ++ ims ++ [T.pack $ "import Controller." ++ ctrlModName] ++ ai

                let injectRoute [] = [T.pack $ "    get " ++ camelName ++ "Path " ++ camelName ++ "Action"]
                    injectRoute (l:ls)
                        | "notFound " `T.isInfixOf` l = (T.pack $ "    get " ++ camelName ++ "Path " ++ camelName ++ "Action") : l : ls
                        | otherwise = l : injectRoute ls

                TIO.writeFile routerFile (T.unlines (injectRoute rLinesWithImport))
                putStrLn $ "Updated " ++ routerFile

            putStrLn "Page scaffolding complete!"
        _ -> putStrLn "Error: Could not find Locale.hs or View.hs templates in add/page/"
