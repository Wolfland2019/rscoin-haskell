module Main where

import Prelude

import Thermite as T

import React as R
import React.DOM as R
import React.DOM.Props as RP
import ReactDOM as RDOM

import Control.Monad.Eff (Eff)
import DOM (DOM) as DOM
import DOM.HTML (window) as DOM
import DOM.HTML.Types (htmlDocumentToParentNode) as DOM
import DOM.HTML.Window (document) as DOM
import DOM.Node.ParentNode (querySelector) as DOM

import Data.Maybe (fromJust)
import Data.Nullable (toMaybe)
import Partial.Unsafe (unsafePartial)

data Action = Increment | Decrement

type State = { counter :: Int }

initialState :: State
initialState = { counter: 0 }

render :: T.Render State _ Action
render dispatch _ state _ =
    [ R.p' [ R.text "Value: "
           , R.text $ show state.counter
           ]
    , R.p' [ R.button [ RP.onClick \_ -> dispatch Increment ]
                      [ R.text "Increment" ]
           , R.button [ RP.onClick \_ -> dispatch Decrement ]
                      [ R.text "Decrement" ]
           ]
    ]

performAction :: T.PerformAction _ State _ Action
performAction Increment _ _ = void $ T.cotransform $ \state -> state { counter = state.counter + 1 }
performAction Decrement _ _ = void $ T.cotransform $ \state -> state { counter = state.counter - 1 }

spec :: T.Spec _ State _ Action
spec = T.simpleSpec performAction render

main :: Eff (dom :: DOM.DOM) Unit
main = void do
    let component = T.createClass spec initialState
    document <- DOM.window >>= DOM.document
    container <- unsafePartial (fromJust <<< toMaybe <$> DOM.querySelector "#container" (DOM.htmlDocumentToParentNode document))
    RDOM.render (R.createFactory component {}) container