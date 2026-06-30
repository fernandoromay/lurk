{-# LANGUAGE OverloadedStrings #-}
module Commands.AddForm
    ( addForm
    ) where

import System.Directory (doesFileExist, doesDirectoryExist, listDirectory)
import System.FilePath ((</>), takeFileName, dropExtension)
import Data.Char (isAlphaNum, toLower, toUpper)
import Data.List (isSuffixOf)
import Control.Monad (when, unless)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Shared (promptChoice, promptCustomDir, capitalize)

addForm :: IO ()
addForm = do
    putStrLn "--- Add Form ---"

    putStrLn ""
    putStrLn "? Where is the module?"
    targetDirChoice <- promptChoice ""
        [ ("Root directory (.)", ".")
        , ("Web/ subdirectory", "Web")
        , ("Custom directory", "")
        ]
    targetDir <- case targetDirChoice of
        "." -> pure "."
        ""  -> promptCustomDir
        custom -> pure custom

    let modPrefix = if targetDir == "." then "" else capitalize targetDir ++ "."

    viewDir <- findViewDir targetDir
    viewFiles <- listHsFiles viewDir
    let excludedPages = ["Prelude", "Partial"]
    let pageNames = filter (`notElem` excludedPages) (map dropExtension viewFiles)

    putStrLn ""
    putStrLn "? What page to embed the form on?"
    putStrLn $ "  (Found " ++ show (length pageNames) ++ " views in " ++ viewDir ++ ")"
    putStrLn ""

    selectedPage <- if null pageNames
        then do
            putStrLn "  No View files found. Will save as Partial."
            pure ""
        else do
            let opts = map (\f -> (f, f)) pageNames ++ [("Multiple pages - save as Partial", "__PARTIAL__")]
            choice <- promptChoice "" opts
            if choice == "__PARTIAL__"
                then pure ""
                else pure choice

    let partialOpt = null selectedPage

    putStrLn ""
    putStrLn "? How do you want to handle the submission?"
    flashChoice <- promptChoice ""
        [ ("Redirect to /", "redirect")
        , ("Show a message", "flash")
        ]
    let useFlash = flashChoice == "flash"

    ctrlDir <- findCtrlDir targetDir
    ctrlFormExists <- doesFileExist (ctrlDir </> "Form.hs")
    ctrlFormPath <- if ctrlFormExists
        then do
            putStrLn ""
            putStrLn "? Where do you want the Action?"
            choice <- promptChoice ""
                [ ("Controller.Form (append to existing)", "form")
                , ("Custom controller", "custom")
                ]
            case choice of
                "form" -> pure (ctrlDir </> "Form.hs")
                _ -> do
                    putStrLn "Controller name (without .hs):"
                    putStr "> "
                    customName <- getLine
                    pure (ctrlDir </> customName ++ ".hs")
        else pure (ctrlDir </> "Form.hs")

    putStrLn ""
    putStrLn "Form name (e.g., contact):"
    putStr "> "
    formNameInput <- getLine
    let formName = map toLower (filter (\c -> isAlphaNum c || c == ' ') formNameInput)
    let actionName = formName ++ "PostAction"
    let formFnName = formName ++ "Form"

    let honeypotField = "honeypot"
    let minTime = "3"

    putStrLn ""
    putStrLn "Generating files..."
    putStrLn ""

    -- Generate Controller/Form.hs
    let redirectPath = if partialOpt then "" else selectedPage
    let pageNameForLocale = if partialOpt then "Partial" else selectedPage
    generateController ctrlFormPath modPrefix formName actionName honeypotField minTime useFlash redirectPath pageNameForLocale

    -- Inject Locale definition
    injectFormLocale targetDir modPrefix formName pageNameForLocale

    -- Generate form function and embed in view
    if partialOpt
        then do
            generatePartialForm targetDir modPrefix formFnName honeypotField useFlash
        else do
            let viewPath = viewDir </> selectedPage ++ ".hs"
            generateViewForm viewPath modPrefix formFnName honeypotField useFlash

    -- Inject setFormLoadTime into GET action
    when (not partialOpt) $ do
        injectSetFormLoadTime ctrlDir selectedPage

    -- Inject route into Router.hs
    let routerPath = "Router.hs"
    routerExists <- doesFileExist routerPath
    when routerExists $ do
        if partialOpt
            then injectPartialRouteComments routerPath actionName
            else injectRoute routerPath ctrlFormPath modPrefix actionName selectedPage

    -- Inject flashHtml helper for flash mode
    when (useFlash && not partialOpt) $ do
        let viewPath = viewDir </> selectedPage ++ ".hs"
        injectFlashHtmlHelper viewPath

    putStrLn "Done!"

----------------------------------------------------------------------
-- FILE FINDING
----------------------------------------------------------------------

findViewDir :: String -> IO String
findViewDir targetDir = do
    let viewDir = targetDir </> "View"
    exists <- doesDirectoryExist viewDir
    if exists then pure viewDir else pure (targetDir </> ".")

findCtrlDir :: String -> IO String
findCtrlDir targetDir = do
    let ctrlDir = targetDir </> "Controller"
    exists <- doesDirectoryExist ctrlDir
    if exists then pure ctrlDir else pure (targetDir </> "Controller")

listHsFiles :: FilePath -> IO [FilePath]
listHsFiles dir = do
    exists <- doesDirectoryExist dir
    if not exists then pure []
    else filter (".hs" `isSuffixOf`) <$> listDirectory dir

----------------------------------------------------------------------
-- CONTROLLER GENERATION
----------------------------------------------------------------------

generateController :: FilePath -> String -> String -> String -> String -> String -> Bool -> String -> String -> IO ()
generateController ctrlPath modPrefix formName actionName honeypotField minTime useFlash redirectPage pageNameForLocale = do
    exists <- doesFileExist ctrlPath
    if exists
        then appendController ctrlPath modPrefix formName actionName honeypotField minTime useFlash redirectPage pageNameForLocale
        else createController ctrlPath modPrefix formName actionName honeypotField minTime useFlash redirectPage pageNameForLocale

createController :: FilePath -> String -> String -> String -> String -> String -> Bool -> String -> String -> IO ()
createController ctrlPath modPrefix formName actionName honeypotField minTime useFlash redirectPage pageNameForLocale = do
    let controllerName = dropExtension (takeFileName ctrlPath)
    let fullModName = modPrefix ++ "Controller." ++ controllerName
    let (redirectPathArg, pathsImport) = case redirectPage of
            "" -> ("\"/\"", "")
            page -> let camelPage = toLower (head page) : tail page
                    in ("(" ++ camelPage ++ "Path ?lang)", "\nimport " ++ modPrefix ++ "Paths")
    let redirectExpr = "redirect " ++ redirectPathArg
    let guardRedirect = if useFlash
            then "(flashError \"Something went wrong, please try again.\" >> " ++ redirectExpr ++ ")"
            else redirectExpr
    let flashCode = if useFlash then
            "\n        flashSuccess \"Your message has been sent!\"\n        " ++ redirectExpr else
            "\n        " ++ redirectExpr
    let rulesName = formName ++ "Rules"
    let content = T.pack $ unlines
            [ "module " ++ fullModName ++ " where"
            , ""
            , "import Lurk.Prelude"
            , "import " ++ modPrefix ++ "Language"
            , "import Lurk.Form" ++ pathsImport
            , "import Lurk.Email.SMTP"
            , "import " ++ modPrefix ++ "Locale." ++ pageNameForLocale ++ " qualified as " ++ pageNameForLocale
            , ""
            , "-- Generated rules (user customizes after)"
            , rulesName ++ " :: (?lang :: Language) => Rule"
            , rulesName ++ " ="
            , "    field \"name\"     (required l.errNameRequired)"
            , "    <> field \"email\"    (required l.errEmailRequired <> isEmail l.errEmailInvalid)"
            , "    <> field \"message\"  (required l.errMessageRequired)"
            , "  where l = " ++ pageNameForLocale ++ "." ++ formName ++ "FormLocale ?lang"
            , ""
            , actionName ++ " :: (?lang :: Language) => Action ()"
            , actionName ++ " = do"
            , "    fd <- runGuards"
            , "        (map ($ " ++ guardRedirect ++ ")"
            , "            [ honeypot \"" ++ honeypotField ++ "\""
            , "            , minSubmitTime " ++ minTime
            , "            , mxRecord \"email\""
            , "            ]"
            , "        )"
            , ""
            , "    fd' <- validate " ++ rulesName ++ " " ++ redirectPathArg ++ " fd"
            , "    let name = getParamDef \"name\" \"\" fd'"
            , "        email = getParamDef \"email\" \"\" fd'"
            , "        message = getParamDef \"message\" \"\" fd'"
            , ""
            , "        -- TODO: Send admin notification email"
            , "        -- mConfig <- liftIO $ smtpConfig \"noreply@yourdomain.com\" \"Your Name\""
            , "        -- case mConfig of"
            , "        --     Just cfg -> sendEmail cfg Email"
            , "        --         { emailTo = \"admin@example.com\""
            , "        --         , emailSubject = \"New contact from \" <> name"
            , "        --         , emailBody = renderHtml (emailTemplate fieldsToPass)"
            , "        --         }"
            , "        --     Nothing -> pure ()"
            , ""
            , "        -- TODO: Send user confirmation email"
            , flashCode
            , ""
            ]
    TIO.writeFile ctrlPath content
    putStrLn $ "Created " ++ ctrlPath

appendController :: FilePath -> String -> String -> String -> String -> String -> Bool -> String -> String -> IO ()
appendController ctrlPath modPrefix formName actionName honeypotField minTime useFlash redirectPage pageNameForLocale = do
    let redirectPathArg = case redirectPage of
            "" -> "\"/\""
            page -> let camelPage = toLower (head page) : tail page
                    in "(" ++ camelPage ++ "Path ?lang)"
    let redirectExpr = "redirect " ++ redirectPathArg
    let flashCode = if useFlash then
            "\n    flashSuccess \"Your message has been sent!\"\n    " ++ redirectExpr else
            "\n    " ++ redirectExpr
    let guardRedirect = if useFlash
            then "(flashError \"Something went wrong, please try again.\" >> " ++ redirectExpr ++ ")"
            else redirectExpr
    -- Inject Paths import if redirecting to a specific page
    content <- TIO.readFile ctrlPath
    let lines' = T.lines content
    unless (null redirectPage) $ do
        let hasPathsImport = any (\l -> "Paths" `T.isInfixOf` l && "import " `T.isPrefixOf` l) lines'
        unless hasPathsImport $ do
            let isImport l = "import " `T.isPrefixOf` T.strip l
            let (beforeImps, impsAndAfter) = break isImport lines'
            let (imps, afterImps) = span isImport impsAndAfter
            let updatedLines = beforeImps ++ imps ++ [T.pack $ "import " ++ modPrefix ++ "Paths"] ++ afterImps
            TIO.writeFile ctrlPath (T.unlines updatedLines)
            -- reload content
            pure ()
    
    -- Inject Validate and Locale imports if needed
    content2 <- TIO.readFile ctrlPath
    let lines2' = T.lines content2
    let hasValidate = any (\l -> "import Lurk.Validate" `T.isInfixOf` l) lines2'
    let localeImport = "import " ++ modPrefix ++ "Locale." ++ pageNameForLocale ++ " qualified as " ++ pageNameForLocale
    let hasLocale = any (\l -> T.pack localeImport `T.isInfixOf` l) lines2'
    
    let isImport l = "import " `T.isPrefixOf` T.strip l
    let (beforeImps, impsAndAfter) = break isImport lines2'
    let (imps, afterImps) = span isImport impsAndAfter
    let newImps = imps
            ++ (if not hasValidate then [T.pack "import Lurk.Validate"] else [])
            ++ (if not hasLocale then [T.pack localeImport] else [])
    
    TIO.writeFile ctrlPath (T.unlines (beforeImps ++ newImps ++ afterImps))

    let rulesName = formName ++ "Rules"
    let newAction = T.pack $ unlines
            [ ""
            , "-- Generated rules (user customizes after)"
            , rulesName ++ " :: (?lang :: Language) => Rule"
            , rulesName ++ " ="
            , "    field \"name\"     (required l.errNameRequired)"
            , "    <> field \"email\"    (required l.errEmailRequired <> isEmail l.errEmailInvalid)"
            , "    <> field \"message\"  (required l.errMessageRequired)"
            , "  where l = " ++ pageNameForLocale ++ "." ++ formName ++ "FormLocale ?lang"
            , ""
            , actionName ++ " :: (?lang :: Language) => Action ()"
            , actionName ++ " = do"
            , "    fd <- runGuards"
            , "        (map ($ " ++ guardRedirect ++ ")"
            , "            [ honeypot \"" ++ honeypotField ++ "\""
            , "            , minSubmitTime " ++ minTime
            , "            , mxRecord \"email\""
            , "            ]"
            , "        )"
            , ""
            , "    fd' <- validate " ++ rulesName ++ " " ++ redirectPathArg ++ " fd"
            , "    let name = getParamDef \"name\" \"\" fd'"
            , "        email = getParamDef \"email\" \"\" fd'"
            , "        message = getParamDef \"message\" \"\" fd'"
            , ""
            , "        -- TODO: Send admin notification email"
            , "        -- mConfig <- liftIO $ smtpConfig \"noreply@yourdomain.com\" \"Your Name\""
            , "        -- case mConfig of"
            , "        --     Just cfg -> sendEmail cfg Email"
            , "        --         { emailTo = \"admin@example.com\""
            , "        --         , emailSubject = \"New contact from \" <> name"
            , "        --         , emailBody = renderHtml (emailTemplate fieldsToPass)"
            , "        --         }"
            , "        --     Nothing -> pure ()"
            , ""
            , "        -- TODO: Send user confirmation email"
            , flashCode
            , ""
            ]
    TIO.appendFile ctrlPath newAction
    putStrLn $ "Appended action to " ++ ctrlPath

----------------------------------------------------------------------
-- VIEW FORM GENERATION — produces a [lurk|...|] function
----------------------------------------------------------------------

generateViewForm :: FilePath -> String -> String -> String -> Bool -> IO ()
generateViewForm viewPath modPrefix formFnName honeypotField useFlash = do
    -- 1. Inject {{ formFnName }} call inside the lurk block (before last |])
    --    Do this FIRST before appending the function (which adds its own |])
    content <- TIO.readFile viewPath
    let lines' = T.lines content
    let closingIdx = findLastClosingIndex lines'
    let embedCall = "  {{" ++ formFnName ++ "}}"
    let (before, after) = splitAt closingIdx lines'
    let newLines = before ++ [T.pack embedCall] ++ after
    TIO.writeFile viewPath (T.unlines newLines)
    putStrLn $ "Embedded {{ " ++ formFnName ++ " }} in lurk block of " ++ viewPath

    -- 2. Append form function at end of file
    let flashLine = if useFlash then "{{ flashHtml }}" else ""
    let formFn = T.pack $ formFnLurkFn formFnName flashLine honeypotField
    TIO.appendFile viewPath ("\n" <> formFn)
    putStrLn $ "Appended " ++ formFnName ++ " function to " ++ viewPath

generatePartialForm :: String -> String -> String -> String -> Bool -> IO ()
generatePartialForm targetDir modPrefix formFnName honeypotField useFlash = do
    let partialPath = targetDir </> "View" </> "Partial.hs"
    exists <- doesFileExist partialPath
    let flashLine = if useFlash then "{{ flashHtml }}" else ""
    let formFn = formFnLurkFn formFnName flashLine honeypotField
    let comment = buildPartialComment formFnName
    if exists
        then do
            TIO.appendFile partialPath ("\n" <> T.pack comment <> T.pack formFn)
            putStrLn $ "Appended " ++ formFnName ++ " to " ++ partialPath
        else do
            let content = T.pack $ unlines
                    [ "{-# LANGUAGE RecordWildCards #-}"
                    , "module " ++ modPrefix ++ "View.Partial where"
                    , ""
                    , "import " ++ modPrefix ++ "View.Prelude"
                    , ""
                    , comment
                    , formFn
                    ]
            TIO.writeFile partialPath content
            putStrLn $ "Created " ++ partialPath

-- | Build a complete form function definition using [lurk|...|]
formFnLurkFn :: String -> String -> String -> String
formFnLurkFn formFnName flashLine honeypotField = unlines
    [ formFnName ++ " :: ViewCtx Language => Html"
    , formFnName ++ " = [lurk|"
    , "<form method=\"POST\" action=\"{{currentPath}}\" style=\"max-width:600px;margin:0 auto;\">"
    , "    <input type=\"hidden\" name=\"_token\" value=\"{{csrfToken}}\">"
    , "    <input type=\"hidden\" name=\"form_load_time\" value=\"\">"
    , if null flashLine then "" else "    " ++ flashLine
    , "    <div style=\"margin-bottom:16px;\">"
    , "        <label for=\"name\" style=\"display:block;margin-bottom:4px;font-weight:600;\">Name</label>"
    , "        <span class=\"field-error\">{{fieldErrors \"name\"}}</span>"
    , "        <input type=\"text\" name=\"name\" id=\"name\" required"
    , "               style=\"width:100%;padding:10px;border:1px solid #ccc;border-radius:4px;font-size:14px;\">"
    , "    </div>"
    , ""
    , "    <div style=\"margin-bottom:16px;\">"
    , "        <label for=\"email\" style=\"display:block;margin-bottom:4px;font-weight:600;\">Email</label>"
    , "        <span class=\"field-error\">{{fieldErrors \"email\"}}</span>"
    , "        <input type=\"email\" name=\"email\" id=\"email\" required"
    , "               style=\"width:100%;padding:10px;border:1px solid #ccc;border-radius:4px;font-size:14px;\">"
    , "    </div>"
    , ""
    , "    <div style=\"margin-bottom:16px;\">"
    , "        <label for=\"message\" style=\"display:block;margin-bottom:4px;font-weight:600;\">Message</label>"
    , "        <span class=\"field-error\">{{fieldErrors \"message\"}}</span>"
    , "        <textarea name=\"message\" id=\"message\" rows=\"5\" required"
    , "                  style=\"width:100%;padding:10px;border:1px solid #ccc;border-radius:4px;font-size:14px;resize:vertical;\"></textarea>"
    , "    </div>"
    , ""
    , "    <!-- Honeypot -->"
    , "    <div style=\"position:absolute;left:-9999px;\" aria-hidden=\"true\">"
    , "        <input type=\"text\" name=\"" ++ honeypotField ++ "\" tabindex=\"-1\" autocomplete=\"off\">"
    , "    </div>"
    , ""
    , "    <button type=\"submit\""
    , "            style=\"background:#2563eb;color:#fff;padding:12px 24px;border:none;border-radius:4px;font-size:16px;cursor:pointer;\">"
    , "        Submit"
    , "    </button>"
    , "</form>"
    , "|]"
    ]

buildPartialComment :: String -> String
buildPartialComment formFnName = unlines
    [ "-- ============================================================"
    , "-- FORM PARTIAL: " ++ formFnName
    , "-- ============================================================"
    , "-- How to use:"
    , "--"
    , "-- 1. Import in your View:"
    , "--      import " ++ formFnName
    , "--"
    , "-- 2. Embed in your View's lurk block:"
    , "--      {{" ++ formFnName ++ "}}"
    , "--"
    , "-- 3. Add POST route to Router.hs:"
    , "--      post homePath contactPostAction"
    , "--"
    , "-- 4. In your GET action, add:"
    , "--      setFormLoadTime  -- remove if not using the guard minSubmitTime"
    , "--      render $ homeView locale"
    , "-- ============================================================"
    ]

----------------------------------------------------------------------
-- FLASH HTML HELPER
----------------------------------------------------------------------

buildFlashHtmlHelper :: String
buildFlashHtmlHelper = unlines
    [ ""
    , "-- Flash message"
    , "flashHtml :: (?ctx :: ViewContext) => Html"
    , "flashHtml = case flash of"
    , "    Nothing -> [lurk||]"
    , "    Just f -> [lurk|"
    , "<style>"
    , "#flash-message { padding:12px 16px; border-radius:4px; margin-bottom:16px; font-size:14px; display:flex; justify-content:space-between; align-items:center; }"
    , "</style>"
    , "<script>"
    , "setTimeout(function(){var e=document.getElementById('flash-message');if(e)e.style.display='none';},5000);"
    , "</script>"
    , "<div id=\"flash-message\" class=\"{{alertClass f}}\">"
    , "  <span>{{flashMessage f}}</span>"
    , "  <button onclick=\"document.getElementById('flash-message').style.display='none'\" style=\"background:none;border:none;font-size:18px;cursor:pointer;color:inherit;\">&times;</button>"
    , "</div>"
    , "|]"
    , "  where"
    , "    alertClass :: Flash -> Text"
    , "    alertClass flash' = case flashLevel flash' of"
    , "        FlashSuccess -> \"alert-success\""
    , "        FlashError   -> \"alert-error\""
    , "        FlashWarning -> \"alert-warning\""
    ]

----------------------------------------------------------------------
-- INJECT setFormLoadTime INTO GET ACTION
----------------------------------------------------------------------

injectSetFormLoadTime :: String -> String -> IO ()
injectSetFormLoadTime ctrlDir pageName = do
    ctrlFiles <- listHsFiles ctrlDir
    mapM_ (tryInject ctrlDir pageName) ctrlFiles

tryInject :: String -> String -> FilePath -> IO ()
tryInject ctrlDir pageName ctrlFile = do
    let ctrlPath = ctrlDir </> ctrlFile
    content <- TIO.readFile ctrlPath
    let camelPage = toLower (head pageName) : tail pageName
    let actionPattern = camelPage ++ "Action"
    let lines' = T.lines content
    case findActionLine actionPattern lines' of
        Nothing -> pure ()
        Just idx -> do
            let afterType = drop (idx + 1) lines'
            let eqOffset = findEqLine afterType
            let eqLineIdx = idx + 1 + eqOffset
            let eqLine = lines' !! eqLineIdx
            let hasDo = "do" `T.isInfixOf` eqLine
            let afterEqLine = drop (eqLineIdx + 1) lines'
            let bodyLines = takeWhile (\l -> not (T.null (T.strip l))) afterEqLine
            let alreadyHas = any (\l -> "setFormLoadTime" `T.isInfixOf` l) bodyLines
            if alreadyHas then pure ()
            else do
                -- Add import for Lurk.Form if not present
                let hasFormImport = any (\l -> "import Lurk.Form" `T.isInfixOf` l) lines'
                let linesWithImport = if hasFormImport then lines'
                        else let (beforeImps, imps) = span (\l -> not ("import " `T.isPrefixOf` T.strip l)) lines'
                                 (imps', afterImps) = span (\l -> "import " `T.isPrefixOf` T.strip l) imps
                             in beforeImps ++ imps' ++ [T.pack "import Lurk.Form (setFormLoadTime)"] ++ afterImps
                let importOffset = if hasFormImport then 0 else 1
                let setFormLine = "    setFormLoadTime  -- remove if not using the guard minSubmitTime"
                if hasDo
                    then do
                        let (before, after) = splitAt (eqLineIdx + 1) linesWithImport
                        TIO.writeFile ctrlPath (T.unlines (before ++ [setFormLine] ++ after))
                        putStrLn $ "Injected setFormLoadTime into " ++ ctrlPath
                    else do
                        -- One-liner: "foo = render $ bar" -> "foo = do\n    setFormLoadTime\n    render $ bar"
                        let adjEqLineIdx = eqLineIdx + importOffset
                        let adjEqLine = linesWithImport !! adjEqLineIdx
                        let newEq = T.stripEnd (fst (T.breakOn "=" adjEqLine)) <> " = do"
                        let rhs = T.strip (snd (T.breakOnEnd "=" adjEqLine))
                        let (beforeEq, rest) = splitAt adjEqLineIdx linesWithImport
                        let newLines = beforeEq ++ [newEq, setFormLine, "    " <> rhs] ++ drop (adjEqLineIdx + 1) rest
                        TIO.writeFile ctrlPath (T.unlines newLines)
                        putStrLn $ "Injected setFormLoadTime into " ++ ctrlPath

findEqLine :: [T.Text] -> Int
findEqLine [] = 0
findEqLine (l:ls)
    | "=" `T.isInfixOf` l && not ("::" `T.isInfixOf` l) = 0
    | otherwise = 1 + findEqLine ls

findActionLine :: String -> [T.Text] -> Maybe Int
findActionLine _ [] = Nothing
findActionLine actionName (l:ls)
    | T.pack actionName `T.isInfixOf` l && ("::" `T.isInfixOf` l || "=" `T.isInfixOf` l) = Just 0
    | otherwise = case findActionLine actionName ls of
        Nothing -> Nothing
        Just idx -> Just (idx + 1)

----------------------------------------------------------------------
-- FLASH HELPER INJECTION
----------------------------------------------------------------------

injectFlashHtmlHelper :: FilePath -> IO ()
injectFlashHtmlHelper viewPath = do
    content <- TIO.readFile viewPath
    let helper = T.pack buildFlashHtmlHelper
    TIO.appendFile viewPath ("\n" <> helper)
    putStrLn $ "Injected flashHtml helper into " ++ viewPath

----------------------------------------------------------------------
-- ROUTE INJECTION
----------------------------------------------------------------------

injectRoute :: FilePath -> FilePath -> String -> String -> String -> IO ()
injectRoute routerPath ctrlPath modPrefix actionName pageName = do
    content <- TIO.readFile routerPath
    let ctrlModName = dropExtension (takeFileName ctrlPath)
    let fullCtrlMod = modPrefix ++ "Controller." ++ ctrlModName
    let rLines = T.lines content

    let hasCtrlImport = any (\l -> ("import " <> T.pack fullCtrlMod) `T.isInfixOf` l) rLines
    let isImport l = "import " `T.isPrefixOf` T.strip l
    let rLinesWithImport = if hasCtrlImport
            then rLines
            else let (bi, r1) = span (not . isImport) rLines
                     (ims, ai) = span isImport r1
                 in bi ++ ims ++ [T.pack $ "import " ++ fullCtrlMod] ++ ai

    let camelPage = toLower (head pageName) : tail pageName
    let getPattern = "get " ++ camelPage ++ "Path "
    let postLine = T.pack $ "    post " ++ camelPage ++ "Path " ++ actionName

    let injectPost [] = [postLine]
        injectPost (l:ls)
            | T.pack getPattern `T.isInfixOf` l = l : postLine : ls
            | "notFound " `T.isInfixOf` l = postLine : l : ls
            | otherwise = l : injectPost ls

    TIO.writeFile routerPath (T.unlines (injectPost rLinesWithImport))
    putStrLn $ "Injected POST route into " ++ routerPath

injectPartialRouteComments :: FilePath -> String -> IO ()
injectPartialRouteComments routerPath actionName = do
    let comments = T.pack $ unlines
            [ ""
            , "-- ============================================================"
            , "-- FORM ROUTE: " ++ actionName
            , "-- ============================================================"
            , "-- Uncomment ONE option:"
            , "--"
            , "-- Option A: Attach to existing page:"
            , "--   post homePath " ++ actionName
            , "--"
            , "-- Option B: Dedicated route:"
            , "--   post contactPath " ++ actionName
            , "--   contactPath = \"/contact/submit\""
            , "-- ============================================================"
            ]
    TIO.appendFile routerPath comments
    putStrLn $ "Added route comments to " ++ routerPath

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

findLastClosingIndex :: [T.Text] -> Int
findLastClosingIndex [] = 0
findLastClosingIndex lines' =
    let indexed = zip [0 :: Int ..] lines'
        closingIndices = [i | (i, l) <- indexed, "|]" `T.isInfixOf` l]
    in if null closingIndices then length lines' else last closingIndices

----------------------------------------------------------------------
-- LOCALE INJECTION
----------------------------------------------------------------------

injectFormLocale :: String -> String -> String -> String -> IO ()
injectFormLocale targetDir modPrefix formName pageNameForLocale = do
    let localeDir = targetDir </> "Locale"
    let localePath = localeDir </> pageNameForLocale ++ ".hs"
    exists <- doesFileExist localePath
    
    let capitalizeFirst (c:cs) = toUpper c : cs
        capitalizeFirst [] = []
    
    let formCamel = capitalizeFirst formName
    let dataName = formCamel ++ "FormLocale"
    let fnName = formName ++ "FormLocale"
    
    let localeContent = unlines
            [ ""
            , "data " ++ dataName ++ " = " ++ dataName
            , "    { errNameRequired :: Text"
            , "    , errEmailRequired :: Text"
            , "    , errEmailInvalid :: Text"
            , "    , errMessageRequired :: Text"
            , "    }"
            , ""
            , fnName ++ " :: Language -> " ++ dataName
            , fnName ++ " EN = " ++ dataName
            , "    { errNameRequired = \"Name is required.\""
            , "    , errEmailRequired = \"Email is required.\""
            , "    , errEmailInvalid = \"Please enter a valid email address.\""
            , "    , errMessageRequired = \"Message is required.\""
            , "    }"
            , fnName ++ " ES = " ++ dataName
            , "    { errNameRequired = \"El nombre es obligatorio.\""
            , "    , errEmailRequired = \"El correo es obligatorio.\""
            , "    , errEmailInvalid = \"Por favor ingresa un correo valido.\""
            , "    , errMessageRequired = \"El mensaje es obligatorio.\""
            , "    }"
            ]
    
    if exists
        then do
            TIO.appendFile localePath (T.pack localeContent)
            putStrLn $ "Injected form locale into " ++ localePath
        else do
            let initialContent = unlines
                    [ "{-# LANGUAGE OverloadedStrings #-}"
                    , "module " ++ modPrefix ++ "Locale." ++ pageNameForLocale ++ " where"
                    , ""
                    , "import Lurk.Prelude"
                    , "import " ++ modPrefix ++ "Language"
                    , localeContent
                    ]
            TIO.writeFile localePath (T.pack initialContent)
            putStrLn $ "Created form locale " ++ localePath
