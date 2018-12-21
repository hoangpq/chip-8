module View exposing (view)

import Array exposing (Array)
import Canvas exposing (Commands)
import CanvasColor as Color
import Dict exposing (Dict)
import Display exposing (Cell, Display)
import Html exposing (..)
import Html.Attributes as Attr
import Html.Events as Events
import Json.Decode as Decode
import List.Extra as List
import Model exposing (Model)
import Msg exposing (Msg(..))


type alias KeyCode =
    Int


view : Model -> Html Msg
view model =
    div [ Attr.style "margin-top" "1em" ]
        [ viewHeader
        , viewCanvas model
        , viewGameSelector model
        , viewKeyMapping model
        ]


viewHeader : Html msg
viewHeader =
    h1 [] [ text "CHIP-8 EMULATOR" ]



{- Canvas and Drawing -}


cellSize =
    10


width =
    64 * cellSize


height =
    32 * cellSize


type alias Color =
    { red : Int
    , green : Int
    , blue : Int
    }


cellColor : Color
cellColor =
    { red = 33
    , green = 37
    , blue = 41
    }


backgroundColor : Color
backgroundColor =
    { red = 253
    , green = 246
    , blue = 227
    }


viewCanvas : Model -> Html Msg
viewCanvas model =
    Canvas.element
        width
        height
        []
        (Canvas.empty
            |> Canvas.clearRect 0 0 width height
            |> renderDisplay model.display
        )


renderDisplay : Display -> Commands -> Commands
renderDisplay displayCells commands =
    displayCells
        |> Array.toList
        |> List.indexedFoldl renderCellRow commands


renderCellRow : Int -> Array Bool -> Commands -> Commands
renderCellRow rowIdx rowCells commands =
    rowCells
        |> Array.toList
        |> List.indexedFoldl (renderCell rowIdx) commands


renderCell : Int -> Int -> Bool -> Commands -> Commands
renderCell rowIdx columnIdx cellValue commands =
    let
        color =
            if cellValue == True then
                Color.rgba cellColor.red cellColor.green cellColor.blue 1

            else
                Color.rgba backgroundColor.red backgroundColor.green backgroundColor.blue 1

        ( x, y ) =
            ( toFloat rowIdx * cellSize, toFloat columnIdx * cellSize )
    in
    commands
        |> Canvas.fillStyle color
        |> Canvas.fillRect x y cellSize cellSize


viewGameSelector : Model -> Html Msg
viewGameSelector model =
    let
        gameOption game =
            option [ Attr.value game.name ] [ text game.name ]

        gameOptions =
            option [ Attr.value "" ] [ text "SELECT GAME" ]
                :: List.map gameOption model.games
    in
    section
        [ Attr.id "games-container" ]
        [ select
            [ Attr.id "game-selector"
            , Attr.class "nes-select is-warning"
            , Attr.style "margin-right" "0.5em"
            , Attr.style "height" "3em"
            , onChange SelectGame
            ]
            gameOptions
        , button
            [ Attr.id "game-reload"
            , Attr.class "nes-btn is-warning"
            , Attr.style "margin-left" "0.5em"
            , Events.onClick ReloadGame
            ]
            [ text "RELOAD" ]
        ]


onChange : (String -> msg) -> Attribute msg
onChange tagger =
    Events.on "change" (Decode.map tagger Events.targetValue)


viewKeyMapping : Model -> Html Msg
viewKeyMapping model =
    let
        keyMapping =
            case model.selectedGame of
                Just game ->
                    game.controls

                Nothing ->
                    []

        toListItems ( keyStr, keyPadValue ) acc =
            li [] [ keyStr |> prettyPrintKey |> text ] :: acc
    in
    div [ Attr.id "key-mapping-container" ]
        [ h3 [] [ text "CONTROLS" ]
        , ul [ Attr.id "key-mapping" ]
            (List.foldl toListItems [] keyMapping)
        ]


prettyPrintKey : String -> String
prettyPrintKey keyStr =
    case keyStr of
        " " ->
            "SPACE"

        "ArrowLeft" ->
            "LEFT ARROW"

        "ArrowUp" ->
            "UP ARROW"

        "ArrowRight" ->
            "RIGHT ARROW"

        "ArrowDown" ->
            "DOWN ARROW"

        alphaNumeric ->
            String.toUpper alphaNumeric
