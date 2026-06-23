{-# LANGUAGE RecordWildCards #-}

module View.Home where

import View.Prelude
import View.Layout.Default
import Locale.Home

homeView :: ViewCtx Language => HomeLocale -> Html
homeView HomeLocale {..} = defaultLayout seo [lurk|
<main class="container py-5">
  <section class="text-center mb-5">
    <h1 class="mb-4">{{heroTitle}}</h1>
    <p class="lead text-secondary mb-5">{{heroSubtitle}}</p>
    <a href="{{heroCtaLink}}" class="btn-primary">{{heroCta}}</a>
  </section>

  <section class="py-5">
    <div class="text-center mb-5">
      <h2 class="mb-3">{{featuresTitle}}</h2>
      <p class="text-secondary">{{featuresSubtitle}}</p>
    </div>
    <div class="feature-list">
      {{forEach features (\f -> (lurk|
        <div class="feature-item">
          <h3>{{f.title}}</h3>
          <p class="text-secondary">{{f.description}}</p>
        </div>
      |))}}
    </div>
  </section>

  <section class="text-center py-5">
    <h2 class="mb-4">{{finalTitle}}</h2>
    <a href="{{finalCtaLink}}" class="btn-primary">{{finalCta}}</a>
  </section>
</main>
|]
