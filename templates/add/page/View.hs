{-# LANGUAGE RecordWildCards #-}
module {{ModPrefix}}View.{{PascalName}} where

import {{ModPrefix}}View.Prelude
import {{ModPrefix}}View.Layout.Default
import {{ModPrefix}}Locale.{{PascalName}}

{{camelName}}View :: ViewCtx Language => {{PascalName}}Locale -> Html
{{camelName}}View {{PascalName}}Locale{..} = defaultLayout seo [lurk|
<main class="flex-grow-1">
  <section class="py-5">
    <div class="container py-5 text-center">
      <h1 class="display-4 fw-bold">{{title}}</h1>
      <p class="lead text-secondary">{{description}}</p>
    </div>
  </section>
</main>
|]
