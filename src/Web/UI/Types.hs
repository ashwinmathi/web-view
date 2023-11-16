{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE UndecidableInstances #-}

module Web.UI.Types where

import Data.Aeson
import Data.Map (Map)
import Data.Map.Strict qualified as M
import Data.String (IsString (..))
import Data.String.Interpolate (i)
import Data.Text (Text, pack, unpack)
import Data.Text qualified as T
import Effectful
import Effectful.Reader.Static
import Effectful.State.Static.Local as ES
import GHC.Generics (Generic)
import Text.Casing (kebab)


type Name = Text
type AttValue = Text


type Attribute = (Name, AttValue)
type Attributes = Map Name AttValue


type Styles = Map Name StyleValue


data Class = Class
  { selector :: Selector
  , properties :: Styles
  }


instance ToJSON Class where
  toJSON c = toJSON c.selector


data Selector = Selector
  { parent :: Maybe Text
  , pseudo :: Maybe Pseudo
  , media :: Maybe Media
  , className :: ClassName
  }
  deriving (Eq, Ord, Generic, ToJSON)


instance IsString Selector where
  fromString s = Selector Nothing Nothing Nothing (fromString s)


data Media
  = MinWidth Int
  | MaxWidth Int
  deriving (Eq, Ord, Generic)
  deriving anyclass (ToJSON)


selectorAddPseudo :: Pseudo -> Selector -> Selector
selectorAddPseudo ps (Selector pr _ m cn) = Selector pr (Just ps) m cn


selectorAddMedia :: Media -> Selector -> Selector
selectorAddMedia m (Selector pr ps _ cn) = Selector pr ps (Just m) cn


selectorAddParent :: Text -> Selector -> Selector
selectorAddParent p (Selector _ ps m c) = Selector (Just p) ps m c


selector :: ClassName -> Selector
selector = Selector Nothing Nothing Nothing


selectorText :: Selector -> T.Text
selectorText s =
  parent s.parent <> "." <> addPseudo s.pseudo (classNameElementText s.media s.parent Nothing s.className)
 where
  parent Nothing = ""
  parent (Just p) = "." <> p <> " "

  addPseudo Nothing c = c
  addPseudo (Just p) c =
    pseudoText p <> "\\:" <> c <> ":" <> pseudoSuffix p


newtype ClassName = ClassName
  { text :: Text
  }
  deriving newtype (Eq, Ord, IsString, ToJSON)


-- | The class name as it appears in the element
classNameElementText :: Maybe Media -> Maybe Text -> Maybe Pseudo -> ClassName -> Text
classNameElementText mm mp mps c =
  addMedia mm . addPseudo mps . addParent mp $ c.text
 where
  addParent Nothing cn = cn
  addParent (Just p) cn = p <> "-" <> cn

  addPseudo :: Maybe Pseudo -> Text -> Text
  addPseudo Nothing cn = cn
  addPseudo (Just p) cn =
    pseudoText p <> ":" <> cn

  addMedia :: Maybe Media -> Text -> Text
  addMedia Nothing cn = cn
  addMedia (Just (MinWidth n)) cn =
    [i|mmnw#{n}-#{cn}|]
  addMedia (Just (MaxWidth n)) cn =
    [i|mmxw#{n}-#{cn}|]


pseudoText :: Pseudo -> Text
pseudoText p = T.toLower $ pack $ show p


pseudoSuffix :: Pseudo -> Text
pseudoSuffix Even = "nth-child(even)"
pseudoSuffix Odd = "nth-child(odd)"
pseudoSuffix p = pseudoText p


data Pseudo
  = Hover
  | Active
  | Even
  | Odd
  deriving (Show, Eq, Ord, Generic, ToJSON)


newtype StyleValue = StyleValue String
  deriving newtype (IsString, Show)


class ToStyleValue a where
  toStyleValue :: a -> StyleValue
  default toStyleValue :: (Show a) => a -> StyleValue
  toStyleValue = StyleValue . kebab . show


instance ToStyleValue String where
  toStyleValue = StyleValue


instance ToStyleValue Text where
  toStyleValue = StyleValue . unpack


instance ToStyleValue Int


-- newtype Px = Px Int deriving (Show)
--
--
-- instance ToStyleValue Px where
--   toStyleValue (Px n) = StyleValue $ show n <> "px"
--
--
-- newtype Rem = Rem Float deriving (Show)
--
--
-- instance ToStyleValue Rem where
--   toStyleValue (Rem f) = StyleValue $ showFFloat (Just 3) f "" <> "rem"

-- Px, converted to Rem
newtype PxRem = PxRem Int
  deriving newtype (Show, ToClassName, Num)


instance ToStyleValue PxRem where
  toStyleValue (PxRem 0) = "0px"
  toStyleValue (PxRem 1) = "1px"
  toStyleValue (PxRem n) = StyleValue $ show ((fromIntegral n :: Float) / 16.0) <> "rem"


newtype Ms = Ms Int
  deriving (Show)
  deriving newtype (Num, ToClassName)


instance ToStyleValue Ms where
  toStyleValue (Ms n) = StyleValue $ show n <> "ms"


newtype HexColor = HexColor Text


instance ToStyleValue HexColor where
  toStyleValue (HexColor s) = StyleValue $ "#" <> unpack (T.dropWhile (== '#') s)


instance IsString HexColor where
  fromString = HexColor . T.dropWhile (== '#') . T.pack


class ToClassName a where
  toClassName :: a -> Text
  default toClassName :: (Show a) => a -> Text
  toClassName = T.toLower . T.pack . show


instance ToClassName Int
instance ToClassName Float


instance ToClassName Text where
  toClassName = id


instance {-# OVERLAPS #-} (ToColor a) => ToClassName a where
  toClassName = colorName


class ToColor a where
  colorValue :: a -> HexColor
  colorName :: a -> Text
  default colorName :: (Show a) => a -> Text
  colorName = T.toLower . pack . show


instance ToColor HexColor where
  colorValue c = c
  colorName (HexColor a) = T.dropWhile (== '#') a


attribute :: Name -> AttValue -> Attribute
attribute n v = (n, v)


data Element = Element
  { name :: Name
  , classes :: [[Class]]
  , attributes :: Attributes
  , children :: [Content]
  }


-- optimized for size, [name, atts, [children]]
instance ToJSON Element where
  toJSON el =
    Array
      [ String el.name
      , toJSON $ flatAttributes el
      , toJSON el.children
      ]


data Content
  = Node Element
  | Text Text
  | Raw Text


instance ToJSON Content where
  toJSON (Node el) = toJSON el
  toJSON (Text t) = String t
  -- TODO: fix json
  toJSON (Raw t) = String t


{- | Views contain their contents, and a list of all styles mentioned during their rendering
newtype View a = View (State ViewState a)
  deriving newtype (Functor, Applicative, Monad, MonadState ViewState)
-}
data ViewState = ViewState
  { contents :: [Content]
  , css :: Map Selector Class
  }


instance Semigroup ViewState where
  va <> vb = ViewState (va.contents <> vb.contents) (va.css <> vb.css)


newtype View ctx a = View {viewState :: Eff [Reader ctx, State ViewState] a}
  deriving newtype (Functor, Applicative, Monad)


instance IsString (View ctx ()) where
  fromString s = modContents (const [Text (pack s)])


runView :: ctx -> View ctx () -> ViewState
runView ctx (View ef) =
  runPureEff . execState (ViewState [] []) . runReader ctx $ ef


-- | A function that modifies an element. Allows for easy chaining and composition
type Mod = Element -> Element


modContents :: ([Content] -> [Content]) -> View c ()
modContents f = View $ do
  ES.modify $ \s -> s{contents = f s.contents}


modCss :: (Map Selector Class -> Map Selector Class) -> View c ()
modCss f = View $ do
  ES.modify $ \s -> s{css = f s.css}


context :: View c c
context = View ask


-- | Run a view with a different context
addContext :: cx -> View cx () -> View c ()
addContext ctx vw = do
  -- runs the sub-view in a different context, saving its state
  -- we need to MERGE it
  let st = runView ctx vw
  View $ ES.modify $ \s -> s <> st


mapRoot :: Mod -> View c ()
mapRoot f = modContents mapContents
 where
  mapContents (Node root : cts) = Node (f root) : cts
  mapContents cts = cts


data Sides a
  = All a
  | TRBL a a a a
  | X a
  | Y a
  | XY a a


-- Num instance is just to support literals
instance (Num a) => Num (Sides a) where
  a + _ = a
  a * _ = a
  abs a = a
  negate a = a
  signum a = a
  fromInteger n = All (fromInteger n)


-- | Attributes, inclusive of class
newtype FlatAttributes = FlatAttributes {attributes :: Attributes}
  deriving (Generic)
  deriving newtype (ToJSON)


flatAttributes :: Element -> FlatAttributes
flatAttributes t =
  FlatAttributes
    $ addClass (mconcat t.classes) t.attributes
 where
  addClass [] atts = atts
  addClass cx atts = M.insert "class" (classAttValue cx) atts

  classAttValue :: [Class] -> T.Text
  classAttValue cx =
    T.intercalate " " $ fmap (\c -> classNameElementText c.selector.media c.selector.parent c.selector.pseudo c.selector.className) cx
