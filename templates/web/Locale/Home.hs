module Locale.Home where

import Locale.Prelude

data HomeLocale = HomeLocale
    { seo :: SEO
    , heroTitle :: Text
    , heroSubtitle :: Text
    , heroCta :: Text
    , heroCtaLink :: Text
    , featuresTitle :: Text
    , featuresSubtitle :: Text
    , features :: [Point]
    , finalTitle :: Text
    , finalCta :: Text
    , finalCtaLink :: Text
    }

data Point = Point
    { title :: Text
    , description :: Text
    }

getLocale :: Language -> HomeLocale
getLocale EN = HomeLocale
    { seo = defaultSEO
        { title = "Lurk - A Haskell Web Framework"
        , metaTitle = "Lurk - Compile-time HTML templates for Haskell"
        , metaDescription = "Build type-safe, high-performance web applications with Lurk. Compile-time templates, built-in i18n, and single-binary deployment."
        , canonical = Just $ domain <> homePath EN
        }
    , heroTitle = "Build web apps with confidence"
    , heroSubtitle = "A lightweight Haskell framework with compile-time HTML templates, type-safe i18n, and single-binary deployment."
    , heroCta = "Get Started"
    , heroCtaLink = "https://github.com/fernandoromay/lurk"
    , featuresTitle = "Why Lurk?"
    , featuresSubtitle = "Everything you need, nothing you don't."
    , features =
        [ Point
            { title = "Compile-time templates"
            , description = "HTML templates are parsed at build time. Typos become compile errors, not runtime surprises."
            }
        , Point
            { title = "Type-safe i18n"
            , description = "Multi-language support via Haskell's type system. Add a language, the compiler tells you what's missing."
            }
        , Point
            { title = "Single binary deployment"
            , description = "Build one executable, rsync it to your server, restart. No runtime dependencies, no asset pipelines."
            }
        , Point
            { title = "Built-in essentials"
            , description = "Sessions, CSRF protection, form validation, SMTP client, and flash messages. Ready from day one."
            }
        , Point
            { title = "Clean architecture"
            , description = "Routes, controllers, views, and locales. A simple MVC pattern that scales without frameworks on top of frameworks."
            }
        , Point
            { title = "Zero JavaScript required"
            , description = "Server-rendered HTML with Haskell functions. No build tools, no node_modules, no hydration step."
            }
        ]
    , finalTitle = "Start building."
    , finalCta = "View on GitHub"
    , finalCtaLink = "https://github.com/fernandoromay/lurk"
    }

getLocale ES = HomeLocale
    { seo = defaultSEO
        { title = "Lurk - Un Framework Web en Haskell"
        , metaTitle = "Lurk - Templates HTML con verificacion en tiempo de compilacion"
        , metaDescription = "Construye aplicaciones web seguras y performantes con Lurk. Templates en tiempo de compilacion, i18n tipado y despliegue en un solo binario."
        , canonical = Just $ domain <> homePath ES
        }
    , heroTitle = "Construye apps web con confianza"
    , heroSubtitle = "Un framework ligero en Haskell con templates HTML en tiempo de compilacion, i18n tipado y despliegue en un solo binario."
    , heroCta = "Empezar"
    , heroCtaLink = "https://github.com/fernandoromay/lurk"
    , featuresTitle = "Por que Lurk?"
    , featuresSubtitle = "Todo lo que necesitas, nada que no."
    , features =
        [ Point
            { title = "Templates en tiempo de compilacion"
            , description = "El HTML se parsea en tiempo de build. Los typos se vuelven errores de compilacion, no de runtime."
            }
        , Point
            { title = "i18n tipado"
            , description = "Soporte multi-idioma via el sistema de tipos de Haskell. Agregas un idioma, el compilador te dice que falta."
            }
        , Point
            { title = "Despliegue en un solo binario"
            , description = "Compilas un ejecutable, lo subes al servidor, reinicias. Sin dependencias de runtime, sin pipelines de assets."
            }
        , Point
            { title = "Lo esencial incluido"
            , description = "Sesiones, proteccion CSRF, validacion de formularios, cliente SMTP y flash messages. Listo desde el dia uno."
            }
        , Point
            { title = "Arquitectura limpia"
            , description = "Rutas, controladores, vistas y locales. Un patron MVC simple que escala sin frameworks encima de frameworks."
            }
        , Point
            { title = "Cero JavaScript necesario"
            , description = "HTML renderizado en el servidor con funciones Haskell. Sin build tools, sin node_modules, sin paso de hidratacion."
            }
        ]
    , finalTitle = "Empeza a construir."
    , finalCta = "Ver en GitHub"
    , finalCtaLink = "https://github.com/fernandoromay/lurk"
    }
