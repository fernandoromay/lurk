module Locale.Partial where

import Locale.Prelude

data NavbarLocale = NavbarLocale
    { homeText :: Text
    , homeLink :: Text
    }

data FooterLocale = FooterLocale
    { notice :: Text
    }

navbarLocale :: Language -> NavbarLocale
navbarLocale EN = NavbarLocale
    { homeText = "Home"
    , homeLink = homePath EN
    }
navbarLocale ES = NavbarLocale
    { homeText = "Inicio"
    , homeLink = homePath ES
    }

footerLocale :: Language -> FooterLocale
footerLocale EN = FooterLocale
    { notice = "This website was built with Lurk."
    }
footerLocale ES = FooterLocale
    { notice = "Este sitio fue desarrollado con Lurk."
    }
