module Lurk.Core
    ( Action
    , LurkRequest
    , request
    , html
    , queryParam
    , setHeader
    , redirect
    , getCookie
    , setSimpleCookie
    , deleteCookie
    , notFound
    , status
    ) where

import Web.Scotty (ActionM, request, html, queryParam, setHeader, redirect, getCookie, setSimpleCookie, deleteCookie, notFound, status)
import Network.Wai (Request)

-- | The core Action monad for Lurk handlers, wrapping Scotty's ActionM.
type Action a = ActionM a

-- | Re-export of WAI Request for domain modules
type LurkRequest = Request
