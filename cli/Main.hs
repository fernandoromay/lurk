{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Environment (getArgs)
import Data.Maybe (fromMaybe)

import qualified Commands.Run as Run
import qualified Commands.Deploy as DeployCmd
import qualified Commands.Kill as Kill
import qualified Commands.New as New
import qualified Commands.AddPage as AddPage
import qualified Commands.AddForm as AddForm
import Shared (availableScaffoldTypes)

data Command
    = Run
    | Build
    | Deploy
    | DeployInit Bool       -- ^ True = also generate GitHub Actions
    | Kill (Maybe String)
    | New String
    | AddPage (Maybe String)
    | AddForm
    | Help (Maybe String)   -- ^ Nothing = general, Just cmd = subcommand help

parseCommand :: [String] -> Either String Command
parseCommand [] = Right (Help Nothing)
parseCommand ["--help"] = Right (Help Nothing)
parseCommand ["-h"] = Right (Help Nothing)

parseCommand ["run"] = Right Run
parseCommand ["run", "--help"] = Right (Help (Just "run"))
parseCommand ["run", "-h"] = Right (Help (Just "run"))

parseCommand ["build"] = Right Build
parseCommand ["build", "--help"] = Right (Help (Just "build"))
parseCommand ["build", "-h"] = Right (Help (Just "build"))

parseCommand ["deploy"] = Right Deploy
parseCommand ["deploy", "--help"] = Right (Help (Just "deploy"))
parseCommand ["deploy", "-h"] = Right (Help (Just "deploy"))
parseCommand ["deploy", "init"] = Right (DeployInit False)
parseCommand ["deploy", "init", "--github-actions"] = Right (DeployInit True)
parseCommand ["deploy", "init", "--help"] = Right (Help (Just "deploy init"))
parseCommand ["deploy", "init", "-h"] = Right (Help (Just "deploy init"))
parseCommand ["deploy", "init", "--github-actions", "--help"] = Right (Help (Just "deploy init"))
parseCommand ["deploy", "init", "--github-actions", "-h"] = Right (Help (Just "deploy init"))

parseCommand ["kill"] = Right (Kill Nothing)
parseCommand ["kill", "--help"] = Right (Help (Just "kill"))
parseCommand ["kill", "-h"] = Right (Help (Just "kill"))
parseCommand ["kill", p] = Right (Kill (Just p))

parseCommand ["new", "--help"] = Right (Help (Just "new"))
parseCommand ["new", "-h"] = Right (Help (Just "new"))
parseCommand ["new", t] = Right (New t)

parseCommand ["add", "page"] = Right (AddPage Nothing)
parseCommand ["add", "page", "--help"] = Right (Help (Just "add page"))
parseCommand ["add", "page", "-h"] = Right (Help (Just "add page"))
parseCommand ["add", "page", n] = Right (AddPage (Just n))
parseCommand ["add", "form"] = Right AddForm
parseCommand ["add", "form", "--help"] = Right (Help (Just "add form"))
parseCommand ["add", "form", "-h"] = Right (Help (Just "add form"))
parseCommand ["add", "--help"] = Right (Help (Just "add"))
parseCommand ["add", "-h"] = Right (Help (Just "add"))

parseCommand args = Left $ "Unknown command: " ++ unwords args

main :: IO ()
main = do
    args <- getArgs
    case parseCommand args of
        Left err -> do
            putStrLn $ "Error: " ++ err
            putStrLn "Run 'lurk --help' for usage."
        Right (Help msub) -> putStrLn (subcommandHelp msub)
        Right cmd -> dispatch cmd

dispatch :: Command -> IO ()
dispatch Run = Run.runProject
dispatch Build = Run.buildProject
dispatch Deploy = DeployCmd.deployCommand
dispatch (DeployInit gh) = DeployCmd.initCommand gh
dispatch (Kill mp) = case mp of
    Nothing -> Kill.killCommand
    Just p  -> Kill.killPort p
dispatch (New t) = New.newProject t
dispatch (AddPage mn) = AddPage.addPage (fromMaybe "" mn)
dispatch AddForm = AddForm.addForm

subcommandHelp :: Maybe String -> String
subcommandHelp Nothing = generalUsage
subcommandHelp (Just cmd) = case cmd of
    "run"         -> runHelp
    "build"       -> buildHelp
    "deploy"      -> deployHelp
    "deploy init" -> deployInitHelp
    "kill"        -> killHelp
    "new"         -> newHelp
    "add"         -> addHelp
    "add page"    -> addPageHelp
    "add form"    -> addFormHelp
    _             -> "Unknown command: " ++ cmd ++ "\nRun 'lurk --help' for usage."

generalUsage :: String
generalUsage = unlines
    [ "Usage: lurk <command> [--help]"
    , ""
    , "Commands:"
    , "  run              Start dev server"
    , "  build            Build project"
    , "  deploy           Deploy via SSH or Docker"
    , "  deploy init      Generate lurk.yaml"
    , "  kill [port]      Kill process on port"
    , "  new <type>       Scaffold a new project"
    , "  add page [name]  Add a new page"
    , "  add form         Add a form to a page"
    , ""
    , "Run 'lurk <command> --help' for more details on a command."
    ]

runHelp :: String
runHelp = unlines
    [ "Usage: lurk run"
    , ""
    , "Start the development server."
    , ""
    , "Loads .env, auto-updates cabal other-modules, then runs"
    , "'cabal run' to start the dev server."
    ]

buildHelp :: String
buildHelp = unlines
    [ "Usage: lurk build"
    , ""
    , "Build the project without starting the server."
    , ""
    , "Loads .env, auto-updates cabal other-modules, then runs"
    , "'cabal build'."
    ]

deployHelp :: String
deployHelp = unlines
    [ "Usage: lurk deploy"
    , ""
    , "Run the deployment pipeline."
    , ""
    , "Reads lurk.yaml and executes: setup, validate, package,"
    , "transfer, activate. Rolls back on failure."
    , ""
    , "Subcommands:"
    , "  init                  Generate lurk.yaml"
    , "  init --github-actions Generate lurk.yaml + GitHub Actions workflow"
    ]

deployInitHelp :: String
deployInitHelp = unlines
    [ "Usage: lurk deploy init [--github-actions]"
    , ""
    , "Generate deployment configuration."
    , ""
    , "Options:"
    , "  --github-actions  Also generate .github/workflows/deploy.yml"
    , ""
    , "Without flags, generates lurk.yaml only."
    ]

killHelp :: String
killHelp = unlines
    [ "Usage: lurk kill [port]"
    , ""
    , "Kill processes holding a TCP port."
    , ""
    , "If no port is given, auto-detects from Main.hs Config record."
    , "Detection priority: Main.hs port value -> .env lookup -> default 3000."
    ]

newHelp :: String
newHelp = unlines
    [ "Usage: lurk new <type>"
    , ""
    , "Scaffold a new project from a template."
    , ""
    , "Available types: " ++ unwords availableScaffoldTypes
    , ""
    , "Prompts for project name and directory."
    ]

addHelp :: String
addHelp = unlines
    [ "Usage: lurk add <page|form>"
    , ""
    , "Add a new page or form to the project."
    , ""
    , "Subcommands:"
    , "  page [name]   Add a new page (Locale, View, Controller, Router)"
    , "  form          Add a form to an existing page"
    , ""
    , "Run 'lurk add <subcommand> --help' for more details."
    ]

addPageHelp :: String
addPageHelp = unlines
    [ "Usage: lurk add page [name]"
    , ""
    , "Add a new page to the project."
    , ""
    , "Creates Locale, View modules, and injects into Paths.hs,"
    , "Controller, and Router.hs."
    , ""
    , "If name is omitted, prompts for it."
    ]

addFormHelp :: String
addFormHelp = unlines
    [ "Usage: lurk add form"
    , ""
    , "Interactive wizard to add a form to an existing page."
    , ""
    , "Prompts for:"
    , "  - Module directory"
    , "  - Which page to embed the form on"
    , "  - Submission handling (redirect or flash message)"
    , "  - Controller location"
    , "  - Form name, honeypot field, min submit time"
    , ""
    , "Generates:"
    , "  - Controller POST action with form guards"
    , "  - Form HTML with inline styles (no Bootstrap)"
    , "  - Route injection into Router.hs"
    , "  - setFormLoadTime in GET action"
    , ""
    , "For flash messages, also generates:"
    , "  - flashHtml helper with inline styles + auto-dismiss JS"
    , "  - Maybe Flash parameter in view signature"
    ]
