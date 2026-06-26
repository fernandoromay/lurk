{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ImplicitParams #-}
module QQSpec (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Lurk.Html (Html(..), renderHtml, toHtml, forEach)
import Lurk.QQ (lurk)
import Data.Text (Text)
import qualified Data.Text as T

-- | Normalize whitespace: strip outer, collapse inner runs to single space.
norm :: Text -> Text
norm = T.unwords . T.words . T.strip

-- Test 1: Single { in literal text (CSS/JS)
testSingleBrace :: Assertion
testSingleBrace = do
    let result = [lurk|<style>body { color: red; }</style>|] :: Html
    renderHtml result @?= "<style>body { color: red; }</style>"

-- Test 2: ? inside string literal — should NOT be replaced
testQuestionInString :: Assertion
testQuestionInString = do
    let result = [lurk|<p>{{"Hello?"}}</p>|] :: Html
    renderHtml result @?= "<p>Hello?</p>"

-- Test 3: Nested lurk with double quotes in HTML attributes
testNestedLurkDoubleQuotes :: Assertion
testNestedLurkDoubleQuotes = do
    let result = [lurk|
<div>
  {{forEach ["a", "b"] (\x -> (lurk|
    <a href="{{x}}">link</a>
  |))}}
</div>
|] :: Html
    norm (renderHtml result) @?= "<div> <a href=\"a\">link</a><a href=\"b\">link</a> </div>"

-- Test 4: Nested lurk with single quotes in HTML attributes
testNestedLurkSingleQuotes :: Assertion
testNestedLurkSingleQuotes = do
    let result = [lurk|
<div>
  {{forEach ["a", "b"] (\x -> (lurk|
    <a href='{{x}}'>link</a>
  |))}}
</div>
|] :: Html
    norm (renderHtml result) @?= "<div> <a href='a'>link</a><a href='b'>link</a> </div>"

-- Test 5: Nested lurk with apostrophe in text
testNestedLurkApostrophe :: Assertion
testNestedLurkApostrophe = do
    let result = [lurk|
<div>
  {{forEach ["it's", "don't"] (\x -> (lurk|
    <p>{{x}}</p>
  |))}}
</div>
|] :: Html
    norm (renderHtml result) @?= "<div> <p>it&#39;s</p><p>don&#39;t</p> </div>"

-- Test 6: Apostrophe in literal text
testApostropheInText :: Assertion
testApostropheInText = do
    let result = [lurk|<p>it's</p>|] :: Html
    renderHtml result @?= "<p>it's</p>"

-- Test 7: Double quotes in literal text
testDoubleQuotesInText :: Assertion
testDoubleQuotesInText = do
    let result = [lurk|<p>say "hello"</p>|] :: Html
    renderHtml result @?= "<p>say \"hello\"</p>"

-- Test 8: Nested lurk conditional with double quotes inside expression
testNestedLurkConditional :: Assertion
testNestedLurkConditional = do
    let result = [lurk|
<div>
  {{forEach ["home", "other"] (\x -> (lurk|
    <a class="{{if x == "home" then "active" else ""}}">{{x}}</a>
  |))}}
</div>
|] :: Html
    norm (renderHtml result) @?= "<div> <a class=\"active\">home</a><a class=\"\">other</a> </div>"

-- Test 9: HTML entity in literal (should NOT be double-escaped)
testHtmlEntityInLiteral :: Assertion
testHtmlEntityInLiteral = do
    let result = [lurk|<p>&quot;hello&quot;</p>|] :: Html
    renderHtml result @?= "<p>&quot;hello&quot;</p>"

-- Test 10: Single { with expressions
testSingleBraceWithExpr :: Assertion
testSingleBraceWithExpr = do
    let result = [lurk|<script>var x = {a: {{1}}, b: {{2}}};</script>|] :: Html
    renderHtml result @?= "<script>var x = {a: 1, b: 2};</script>"

-- Test 11: ?lang as implicit param (should be replaced)
testImplicitParam :: Assertion
testImplicitParam = do
    let result = [lurk|<p>{{"test"}}</p>|] :: Html
    renderHtml result @?= "<p>test</p>"

-- Test 12: Apostrophe inside nested lurk rendered as Text (the real bug scenario)
testApostropheInNestedLurkText :: Assertion
testApostropheInNestedLurkText = do
    let result = [lurk|
<div>
  {{forEach ["Deploy, don't build"] (\x -> (lurk|
    <span>{{x}}</span>
  |))}}
</div>
|] :: Html
    norm (renderHtml result) @?= "<div> <span>Deploy, don&#39;t build</span> </div>"

tests :: TestTree
tests = testGroup "QQ"
    [ testCase "single { in literal" testSingleBrace
    , testCase "? in string literal" testQuestionInString
    , testCase "nested lurk with double quotes" testNestedLurkDoubleQuotes
    , testCase "nested lurk with single quotes" testNestedLurkSingleQuotes
    , testCase "nested lurk with apostrophe" testNestedLurkApostrophe
    , testCase "apostrophe in text" testApostropheInText
    , testCase "double quotes in text" testDoubleQuotesInText
    , testCase "nested lurk conditional with quotes" testNestedLurkConditional
    , testCase "HTML entity not double-escaped" testHtmlEntityInLiteral
    , testCase "single { with expressions" testSingleBraceWithExpr
    , testCase "implicit param works" testImplicitParam
    , testCase "apostrophe in nested lurk text" testApostropheInNestedLurkText
    ]
