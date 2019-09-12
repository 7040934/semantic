module Data.Source.Spec (spec, testTree) where

import Data.Range
import Data.Source
import Data.Span
import qualified Data.Text as Text

import Test.Hspec

import qualified Generators as Gen
import           Hedgehog hiding (Range)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range
import qualified Test.Tasty as Tasty
import           Test.Tasty.Hedgehog (testProperty)

prop :: HasCallStack => String -> (Source -> PropertyT IO ()) -> Tasty.TestTree
prop desc f
  = testProperty desc
  . property
  $ forAll (Gen.source (Hedgehog.Range.linear 0 100))
  >>= f

testTree :: Tasty.TestTree
testTree = Tasty.testGroup "Data.Source"
  [ Tasty.testGroup "sourceLineRanges"
    [ prop "produces 1 more range than there are newlines" $ \ source -> do
        summarize source
        length (sourceLineRanges source) === length (Text.splitOn "\r\n" (toText source) >>= Text.splitOn "\r" >>= Text.splitOn "\n")

    , prop "produces exhaustive ranges" $ \ source -> do
        summarize source
        foldMap (`slice` source) (sourceLineRanges source) === source
    ]

  , Tasty.testGroup "spanToRange"
    [ prop "computes single-line ranges" $ \ source -> do
        let ranges = sourceLineRanges source
        let spans = zipWith (\ i Range {..} -> Span (Pos i 1) (Pos i (succ (end - start)))) [1..] ranges
        fmap (spanToRange source) spans === ranges

    , prop "computes multi-line ranges" $
        \ source ->
          spanToRange source (totalSpan source) === totalRange source

    , prop "computes sub-line ranges" $
        \ s -> let source = "*" <> s <> "*" in
          spanToRange source (insetSpan (totalSpan source)) === insetRange (totalRange source)

    , testProperty "inverse of rangeToSpan" . property $ do
        a <- forAll . Gen.source $ Hedgehog.Range.linear 0 100
        b <- forAll . Gen.source $ Hedgehog.Range.linear 0 100
        let s = a <> "\n" <> b in spanToRange s (totalSpan s) === totalRange s
    ]

  ,  testProperty "rangeToSpan inverse of spanToRange" . property $ do
      a <- forAll . Gen.source $ Hedgehog.Range.linear 0 100
      b <- forAll . Gen.source $ Hedgehog.Range.linear 0 100
      let s = a <> "\n" <> b in rangeToSpan s (totalRange s) === totalSpan s

  , Tasty.testGroup "totalSpan"
    [ testProperty "covers single lines" . property $ do
        n <- forAll $ Gen.int (Hedgehog.Range.linear 0 100)
        totalSpan (fromText (Text.replicate n "*")) === Span (Pos 1 1) (Pos 1 (max 1 (succ n)))

    , testProperty "covers multiple lines" . property $ do
        n <- forAll $ Gen.int (Hedgehog.Range.linear 0 100)
        totalSpan (fromText (Text.intersperse '\n' (Text.replicate n "*"))) === Span (Pos 1 1) (Pos (max 1 n) (if n > 0 then 2 else 1))
    ]

  ]
  where summarize src = do
          let lines = sourceLines src
          -- FIXME: this should be using cover (reverted in 1b427b995), but that leads to flaky tests: hedgehog’s 'cover' implementation fails tests instead of warning, and currently has no equivalent to 'checkCoverage'.
          classify "empty"          $ nullSource src
          classify "single-line"    $ length lines == 1
          classify "multiple lines" $ length lines >  1

spec :: Spec
spec = do
  describe "newlineIndices" $ do
    it "finds \\n" $
      let source = "a\nb" in
      newlineIndices source `shouldBe` [1]
    it "finds \\r" $
      let source = "a\rb" in
      newlineIndices source `shouldBe` [1]
    it "finds \\r\\n" $
      let source = "a\r\nb" in
      newlineIndices source `shouldBe` [2]
    it "finds intermixed line endings" $
      let source = "hi\r}\r}\n xxx \r a" in
      newlineIndices source `shouldBe` [2, 4, 6, 12]

insetSpan :: Span -> Span
insetSpan sourceSpan = sourceSpan { spanStart = (spanStart sourceSpan) { posColumn = succ (posColumn (spanStart sourceSpan)) }
                                  , spanEnd = (spanEnd sourceSpan) { posColumn = pred (posColumn (spanEnd sourceSpan)) } }

insetRange :: Range -> Range
insetRange Range {..} = Range (succ start) (pred end)
