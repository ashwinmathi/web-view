module Test.RenderSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Skeletest
import Web.View
import Web.View.Render (Line (..), LineEnd (..), classNameForAttribute, renderCSS, renderLines, selectorText)
import Web.View.Style
import Web.View.Types
import Web.View.View (ViewState (..), runView, tag')
import Prelude hiding (span)


spec :: Spec
spec = do
  describe "render" $ do
    describe "output" $ do
      it "should render simple output" $ do
        renderText (el_ "hi") `shouldBe` "<div>hi</div>"

      it "should render two elements" $ do
        renderText (el_ "hello" >> el_ "world") `shouldBe` "<div>hello</div>\n<div>world</div>"

      it "should match basic output with styles" $ do
        golden <- goldenFile "test/resources/basic.txt"
        let out = renderText $ col (pad 10) $ el bold "hello" >> el_ "world"
        out `shouldBe` golden

    describe "escape" $ do
      it "should escape properly" $ do
        golden <- goldenFile "test/resources/escaping.txt"
        let out = renderText $ do
              el (att "title" "I have some apos' and quotes \" and I'm a <<great>> attribute!!!") "I am <malicious> &apos;user"
              el (att "title" "I have some apos' and quotes \" and I'm a <<great>> attribute!!!") $ do
                el_ "I am <malicious> &apos;user"
                el_ "I am another <malicious> &apos;user"
        out `shouldBe` golden

      it "should escape properly" $ do
        golden <- goldenFile "test/resources/raw.txt"
        let out = renderText $ el bold $ raw "<svg>&\"'</svg>"
        out `shouldBe` golden

    describe "empty rules" $ do
      it "should skip css class when no css attributes" $ do
        let view = do
              el (addClass $ cls "empty") "i have no css"
              el bold "i have some css"
        renderLines (renderCSS (runCSS view)) `shouldBe` ".bold { font-weight:bold }"

      it "should skip css element when no css rules" $ do
        let res = renderText $ el (addClass $ cls "empty") "i have no css"
        res `shouldBe` "<div class='empty'>i have no css</div>"

    describe "inline" $ do
      it "renderLines should respect inline text " $ do
        renderLines [Line Inline 0 "one ", Line Inline 0 "two"] `shouldBe` "one two"

      it "renderLines should respect inline tags " $ do
        renderLines [Line Inline 0 "one ", Line Inline 0 "two ", Line Inline 0 "<span>/</span>", Line Inline 0 " three"] `shouldBe` "one two <span>/</span> three"

      it "should render text and inline elements inline" $ do
        let span = tag' (Element True "span") :: Mod -> View c () -> View c ()
        let res =
              renderText $ do
                text "one "
                text "two "
                span id "/"
                text " three"
        res `shouldBe` "one two <span>/</span> three"

    describe "indentation" $ do
      it "should nested indent" $ do
        golden <- goldenFile "test/resources/nested.txt"
        let out = renderText $ do
              el_ $ do
                el_ $ do
                  el_ "HI"
        out `shouldBe` golden

    describe "selectors" $ do
      it "normal selector" $ do
        let sel = selector "myclass"
        selectorText sel `shouldBe` ".myclass"

      it "pseudo selector" $ do
        let sel = (selector "myclass"){pseudo = Just Hover}
        classNameForAttribute Nothing Nothing Nothing sel.pseudo sel.className `shouldBe` "hover:myclass"
        selectorText sel `shouldBe` ".hover\\:myclass:hover"

      it "it should include ancestor in selector" $ do
        classNameForAttribute Nothing (Just "parent") Nothing Nothing "myclass" `shouldBe` "parent-myclass"
        let sel = (selector "myclass"){ancestor = Just "parent"}
        selectorText sel `shouldBe` ".parent .parent-myclass"

      it "psuedo + parent" $ do
        let sel = (selector "myclass"){ancestor = Just "parent", pseudo = Just Hover}
        selectorText sel `shouldBe` ".parent .hover\\:parent-myclass:hover"

      it "child" $ do
        let sel = (selector "myclass"){child = Just "mychild"}
        classNameForAttribute Nothing Nothing sel.child Nothing sel.className `shouldBe` "myclass-mychild"
        selectorText sel `shouldBe` ".myclass-mychild > .mychild"

        let sel2 = (selector "myclass"){child = Just AllChildren}
        classNameForAttribute Nothing Nothing sel2.child Nothing sel2.className `shouldBe` "myclass-all"
        selectorText sel2 `shouldBe` ".myclass-all > *"


-- describe "child combinator" $ do
--   it "should include child combinator in definition"  $ do

goldenFile :: FilePath -> IO Text
goldenFile fp = do
  inp <- T.readFile fp
  pure $ T.dropWhileEnd (== '\n') inp


runCSS :: View () () -> CSS
runCSS view = (runView () view).css
