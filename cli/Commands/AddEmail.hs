{-# LANGUAGE OverloadedStrings #-}
module Commands.AddEmail
    ( addEmail
    ) where

import System.Directory (doesFileExist, doesDirectoryExist, listDirectory, createDirectoryIfMissing)
import System.FilePath ((</>), takeFileName, dropExtension)
import Data.Char (isAlphaNum, toLower, toUpper)
import Data.List (isSuffixOf)
import Control.Monad (when, unless)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Shared ( promptChoice, promptCustomDir, capitalize
              , parseLanguageConstructors, scanControllers, scanActions
              , injectImport, isImportLine )

addEmail :: String -> IO ()
addEmail defaultName = do
    putStrLn "--- Add Email ---"

    -- 1. Email name
    putStrLn ""
    putStrLn "Email name (e.g., Welcome, Contact):"
    putStr "> "
    nameInput <- if not (null defaultName)
        then pure defaultName
        else getLine
    let cleanName = filter (\c -> isAlphaNum c || c == ' ' || c == '-') nameInput
    let wordsList = words $ map (\c -> if c == '-' then ' ' else c) cleanName
    let pascalName = concatMap capitalize wordsList
    let camelName = case wordsList of
            [] -> ""
            (w:ws) -> map toLower w ++ concatMap capitalize ws

    -- 2. Select type
    putStrLn ""
    typeChoice <- promptChoice "Email type:"
        [ ("Admin notification on submission", "admin")
        , ("Thank-you for submission", "thanks")
        ]
    let isLocalized = typeChoice == "thanks"

    -- 3. Ask dir (before localized question, per user's design)
    putStrLn ""
    targetDir <- promptChoice "Where is the module located?"
        [ ("Root directory (.)", ".")
        , ("Web/ subdirectory", "Web")
        , ("Custom directory", "")
        ]
    targetDirFinal <- case targetDir of
        "." -> pure "."
        "" -> promptCustomDir
        custom -> pure custom

    let modPrefix = if targetDirFinal == "." then "" else capitalize targetDirFinal ++ "."

    -- 4. [If localized] Scan Language.hs for available languages
    langs <- if isLocalized
        then do
            let langFile = targetDirFinal </> "Language.hs"
            parsedLangs <- parseLanguageConstructors langFile
            if null parsedLangs
                then do
                    putStrLn "Warning: No languages found in Language.hs. Using EN as default."
                    pure ["EN"]
                else do
                    putStrLn $ "Found languages: " ++ unwords parsedLangs
                    pure parsedLangs
        else pure []

    -- 5. Do you want to use this template right now?
    putStrLn ""
    useNow <- promptChoice "Do you want to use this template right now?"
        [ ("Yes, inject into a controller", "yes")
        , ("No, just generate the files", "no")
        ]
    let injectNow = useNow == "yes"

    -- 6. Determine controller and action (if injecting)
    (mCtrlPath, mActionName) <- if injectNow
        then do
            controllers <- scanControllers targetDirFinal
            if null controllers
                then do
                    putStrLn $ "Warning: No controllers found in " ++ targetDirFinal ++ "/Controller/"
                    pure (Nothing, Nothing)
                else do
                    ctrlChoice <- if length controllers == 1
                        then do
                            putStrLn $ "Controller: " ++ head controllers
                            pure (head controllers)
                        else promptChoice "Controller:" [ (c, c) | c <- controllers ]
                    let ctrlPath = targetDirFinal </> "Controller" </> ctrlChoice

                    actions <- scanActions ctrlPath
                    if null actions
                        then do
                            putStrLn "Warning: No Action () signatures found in controller."
                            pure (Just ctrlPath, Nothing)
                        else do
                            actionChoice <- if length actions == 1
                                then do
                                    putStrLn $ "Action: " ++ head actions
                                    pure (head actions)
                                else promptChoice "Action:" [ (a, a) | a <- actions ]
                            pure (Just ctrlPath, Just actionChoice)
        else pure (Nothing, Nothing)

    -- 7. Generate files
    putStrLn ""
    putStrLn "Generating files..."

    -- Create View/Email/ directory
    let viewDir = targetDirFinal </> "View" </> "Email"
    createDirectoryIfMissing True viewDir
    let viewPath = viewDir </> pascalName ++ ".hs"

    -- Generate view file
    let viewContent = if isLocalized
            then generateThankYouView modPrefix pascalName camelName langs
            else generateAdminView modPrefix pascalName camelName
    TIO.writeFile viewPath viewContent
    putStrLn $ "Created " ++ viewPath

    -- Generate locale file (if localized)
    when isLocalized $ do
        let localeDir = targetDirFinal </> "Locale" </> "Email"
        createDirectoryIfMissing True localeDir
        let localePath = localeDir </> pascalName ++ ".hs"
        let localeContent = generateLocale modPrefix pascalName camelName langs
        TIO.writeFile localePath localeContent
        putStrLn $ "Created " ++ localePath

    -- 8. Inject into controller (if selected)
    case (mCtrlPath, mActionName) of
        (Just ctrlPath, Just actionName) -> do
            -- Inject imports
            let viewImport = "import " ++ modPrefix ++ "View.Email." ++ pascalName
            injectImport ctrlPath (T.pack viewImport)
            putStrLn $ "Imported View.Email." ++ pascalName ++ " into " ++ ctrlPath

            when isLocalized $ do
                let localeImport = "import " ++ modPrefix ++ "Locale.Email." ++ pascalName ++ " qualified as " ++ pascalName ++ "Locale"
                injectImport ctrlPath (T.pack localeImport)
                putStrLn $ "Imported Locale.Email." ++ pascalName ++ " into " ++ ctrlPath

            -- Inject send code
            injectSendCode ctrlPath actionName pascalName camelName isLocalized
            putStrLn $ "Injected send code (TODO) into " ++ actionName ++ " in " ++ ctrlPath

        (Just ctrlPath, Nothing) -> do
            -- Inject imports only
            let viewImport = "import " ++ modPrefix ++ "View.Email." ++ pascalName
            injectImport ctrlPath (T.pack viewImport)
            putStrLn $ "Imported View.Email." ++ pascalName ++ " into " ++ ctrlPath

            when isLocalized $ do
                let localeImport = "import " ++ modPrefix ++ "Locale.Email." ++ pascalName ++ " qualified as " ++ pascalName ++ "Locale"
                injectImport ctrlPath (T.pack localeImport)
                putStrLn $ "Imported Locale.Email." ++ pascalName ++ " into " ++ ctrlPath

            putStrLn "Warning: No action selected. Imports injected, but send code not added."

        _ -> pure ()

    -- 9. Add usage instructions to view file (if not injecting)
    unless injectNow $ do
        let usageBlock = generateUsage modPrefix pascalName camelName isLocalized
        TIO.appendFile viewPath ("\n" <> usageBlock)
        putStrLn $ "Added usage instructions to " ++ viewPath

    putStrLn "Done!"

----------------------------------------------------------------------
-- VIEW GENERATION
----------------------------------------------------------------------

-- | Generate admin notification view (fields record, no locale)
generateAdminView :: String -> String -> String -> T.Text
generateAdminView modPrefix pascalName camelName = T.pack $ unlines
    [ "{-# LANGUAGE RecordWildCards #-}"
    , "module " ++ modPrefix ++ "View.Email." ++ pascalName ++ " where"
    , ""
    , "import Lurk.Prelude"
    , ""
    , "data " ++ pascalName ++ "Fields = " ++ pascalName ++ "Fields"
    , "    { name  :: Text"
    , "    , email :: Text"
    , "    -- TODO: add more fields as needed"
    , "    }"
    , ""
    , "-- | HTML version"
    , camelName ++ " :: " ++ pascalName ++ "Fields -> Html"
    , camelName ++ " " ++ pascalName ++ "Fields{..} = [lurk|"
    , "<!DOCTYPE html>"
    , "<html><head></head>"
    , "<body style=\"font-family: Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto;\">"
    , "  <div style=\"border-bottom: 2px solid #000; padding-bottom: 20px; margin-bottom: 30px;\">"
    , "    <h1>TODO: Add title here</h1>"
    , "  </div>"
    , "  <div>"
    , "    <p><strong>Name:</strong> {{name}}</p>"
    , "    <p><strong>Email:</strong> {{email}}</p>"
    , "    <p>TODO: Add body content here</p>"
    , "  </div>"
    , "</body></html>"
    , "|]"
    , ""
    , "-- | Plain text version"
    , camelName ++ "Text :: " ++ pascalName ++ "Fields -> Text"
    , camelName ++ "Text " ++ pascalName ++ "Fields{..} = T.unlines"
    , "    [ \"TODO: Add title here\""
    , "    , \"\""
    , "    , \"Name: \" <> name"
    , "    , \"Email: \" <> email"
    , "    , \"\""
    , "    , \"TODO: Add body content here\""
    , "    ]"
    ]

-- | Generate thank-you view (parameters, locale)
generateThankYouView :: String -> String -> String -> [String] -> T.Text
generateThankYouView modPrefix pascalName camelName _langs = T.pack $ unlines
    [ "{-# LANGUAGE RecordWildCards #-}"
    , "module " ++ modPrefix ++ "View.Email." ++ pascalName ++ " where"
    , ""
    , "import Lurk.Prelude"
    , "import " ++ modPrefix ++ "Language"
    , "import " ++ modPrefix ++ "Locale.Email." ++ pascalName
    , ""
    , "-- | HTML version"
    , camelName ++ " :: (?lang :: Language) => Text -> Html"
    , camelName ++ " name = [lurk|"
    , "<!DOCTYPE html>"
    , "<html><head></head>"
    , "<body style=\"font-family: Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto;\">"
    , "  <div style=\"border-bottom: 2px solid #000; padding-bottom: 20px; margin-bottom: 30px;\">"
    , "    <h1>{{l.greeting}} {{name}}</h1>"
    , "  </div>"
    , "  <div>"
    , "    <p>{{l.body}}</p>"
    , "    <p>{{l.signoff}}</p>"
    , "  </div>"
    , "</body></html>"
    , "|]"
    , "  where l = locale ?lang"
    , ""
    , "-- | Plain text version"
    , camelName ++ "Text :: (?lang :: Language) => Text -> Text"
    , camelName ++ "Text name = T.unlines"
    , "    [ T.unpack (l.greeting) ++ \" \" ++ T.unpack name"
    , "    , \"\""
    , "    , T.unpack l.body"
    , "    , \"\""
    , "    , T.unpack l.signoff"
    , "    ]"
    , "  where l = locale ?lang"
    ]

----------------------------------------------------------------------
-- LOCALE GENERATION
----------------------------------------------------------------------

-- | Generate locale file with English stubs for all languages
generateLocale :: String -> String -> String -> [String] -> T.Text
generateLocale modPrefix pascalName _camelName langs = T.pack $ unlines
    [ "module " ++ modPrefix ++ "Locale.Email." ++ pascalName ++ " where"
    , ""
    , "import " ++ modPrefix ++ "Language"
    , ""
    , "data " ++ pascalName ++ "Locale = " ++ pascalName ++ "Locale"
    , "    { subject :: Text"
    , "    , greeting :: Text"
    , "    , body :: Text"
    , "    , signoff :: Text"
    , "    }"
    , ""
    , "locale :: Language -> " ++ pascalName ++ "Locale"
    ] ++ unlines (map generateLangCase langs)
  where
    generateLangCase lang = "locale " ++ lang ++ " = " ++ pascalName ++ "Locale\n"
        ++ "    { subject = \"TODO: email subject\"\n"
        ++ "    , greeting = \"Hello\"\n"
        ++ "    , body = \"TODO: email body content\"\n"
        ++ "    , signoff = \"Best regards\"\n"
        ++ "    }"

----------------------------------------------------------------------
-- SEND CODE INJECTION
----------------------------------------------------------------------

-- | Inject commented send code into the controller action
injectSendCode :: FilePath -> String -> String -> String -> Bool -> IO ()
injectSendCode ctrlPath actionName pascalName camelName isLocalized = do
    content <- TIO.readFile ctrlPath
    let lines' = T.lines content
    case findActionEnd lines' actionName of
        Nothing -> putStrLn $ "Warning: Could not find end of " ++ actionName ++ " in " ++ ctrlPath
        Just idx -> do
            let sendBlock = T.pack $ generateSendBlock pascalName camelName isLocalized
            let (before, after) = splitAt idx lines'
            TIO.writeFile ctrlPath (T.unlines (before ++ [sendBlock] ++ after))

-- | Find the line index where a do block ends (before redirect or end of action)
findActionStart :: [T.Text] -> String -> Maybe Int
findActionStart [] _ = Nothing
findActionStart (l:ls) name
    | T.pack name `T.isInfixOf` l && ("::" `T.isInfixOf` l || "=" `T.isInfixOf` l) = Just 0
    | otherwise = case findActionStart ls name of
        Nothing -> Nothing
        Just idx -> Just (idx + 1)

findActionEnd :: [T.Text] -> String -> Maybe Int
findActionEnd lines' actionName = do
    startIdx <- findActionStart lines' actionName
    -- startIdx points to the type signature (e.g., "home :: Action ()")
    -- Find the implementation line (e.g., "home = do") which comes after
    let implOffset = findImplLine (drop (startIdx + 1) lines') actionName
    -- Skip past the implementation line itself (e.g., "home = do") + any body lines
    let bodyStart = startIdx + 1 + implOffset + 1
    let afterBody = drop bodyStart lines'
    let endOffset = findDoBlockEnd afterBody
    pure (bodyStart + endOffset)

-- | Find the implementation line (e.g., "name = do") after a type signature
findImplLine :: [T.Text] -> String -> Int
findImplLine [] _ = 0
findImplLine (l:ls) name
    | T.pack name `T.isInfixOf` l && "=" `T.isInfixOf` l && not ("::" `T.isInfixOf` l) = 0
    | otherwise = 1 + findImplLine ls name

-- | Find where a do block ends: last non-empty line before next top-level definition or EOF
findDoBlockEnd :: [T.Text] -> Int
findDoBlockEnd [] = 0
findDoBlockEnd ls = go 0 0 ls
  where
    go _ lastN [] = lastN
    go n lastN (x:xs)
        | T.null (T.strip x) = go (n + 1) lastN xs
        -- Top-level definition starts with no indentation and has :: or =
        | not (T.null x) && T.head x /= ' ' && T.head x /= '\t'
          && ("::" `T.isInfixOf` x || "=" `T.isInfixOf` x) = lastN
        | otherwise = go (n + 1) (n + 1) xs

-- | Generate the commented send code block
generateSendBlock :: String -> String -> Bool -> String
generateSendBlock pascalName camelName isLocalized = unlines
    [ ""
    , "    -- TODO: Send " ++ pascalName ++ " email"
    , "    -- mConfig <- liftIO $ smtpConfig \"from@example.com\" \"From Name\""
    , "    -- case mConfig of"
    , "    --     Just config -> do"
    , "    --         let body = renderHtml (" ++ camelName ++ " TODO-args)"
    , "    --         sendEmail config Email"
    , "    --             { emailTo = TODO-recipient"
    , "    --             , emailSubject = " ++ subjectExpr
    , "    --             , emailHtml = body"
    , "    --             }"
    , "    --     Nothing -> pure ()"
    ]
  where
    subjectExpr = if isLocalized
        then pascalName ++ "Locale.subject (" ++ pascalName ++ "Locale.locale ?lang)"
        else "\"TODO: subject\""

----------------------------------------------------------------------
-- USAGE INSTRUCTIONS
----------------------------------------------------------------------

-- | Generate usage instructions block
generateUsage :: String -> String -> String -> Bool -> T.Text
generateUsage modPrefix pascalName camelName isLocalized = T.pack $ unlines $
    [ "-- ============================================================"
    , "-- USAGE: " ++ pascalName ++ " Email"
    , "-- ============================================================"
    , "-- Import in your controller:"
    , "--   import " ++ modPrefix ++ "View.Email." ++ pascalName
    ] ++ (if isLocalized
        then ["--   import " ++ modPrefix ++ "Locale.Email." ++ pascalName ++ " qualified as " ++ pascalName ++ "Locale"]
        else []) ++
    [ "--"
    , "-- Load SMTP config (add to your controller or a shared module):"
    , "--   import Lurk.Email.SMTP (smtpConfig, sendEmail, Email(..))"
    , "--"
    , "-- Send the email:"
    , "--   mConfig <- liftIO $ smtpConfig \"from@example.com\" \"From Name\""
    , "--   case mConfig of"
    , "--       Just config -> do"
    , "--           let body = renderHtml (" ++ camelName ++ " fields-or-args)"
    , "--           sendEmail config Email"
    , "--               { emailTo = \"recipient@example.com\""
    , "--               , emailSubject = \"TODO: subject\""
    , "--               , emailHtml = body"
    , "--               }"
    , "--       Nothing -> pure ()"
    , "-- ============================================================"
    ]
