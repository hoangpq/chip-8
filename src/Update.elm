port module Update exposing (update)

--import Keyboard exposing (KeyCode)

import Array exposing (Array)
import Dict
import Display
import FetchDecodeExecuteLoop
import Flags exposing (Flags)
import KeyCode exposing (KeyCode)
import Keypad
import List.Extra as List
import Memory
import Model exposing (Model)
import Msg exposing (Msg(..))
import Registers exposing (Registers)
import Timers
import Types exposing (Value8Bit)
import Utils exposing (noCmd)


addKeyCode : Maybe KeyCode -> Model -> ( Model, Cmd Msg )
addKeyCode maybeKeyCode model =
    case maybeKeyCode of
        Just keyCode ->
            let
                newKeypad =
                    model
                        |> Model.getKeypad
                        |> Keypad.addKeyPress keyCode
            in
            model
                |> Model.setKeypad newKeypad
                |> checkIfWaitingForKeyPress keyCode

        _ ->
            ( model, Cmd.none )


removeKeyCode : Maybe KeyCode -> Model -> ( Model, Cmd Msg )
removeKeyCode maybeKeyCode model =
    case maybeKeyCode of
        Just keyCode ->
            let
                newKeypad =
                    model
                        |> Model.getKeypad
                        |> Keypad.removeKeyPress keyCode
            in
            model |> Model.setKeypad newKeypad |> noCmd

        Nothing ->
            ( model, Cmd.none )


checkIfWaitingForKeyPress : KeyCode -> Model -> ( Model, Cmd Msg )
checkIfWaitingForKeyPress keyCode model =
    case model |> Model.getFlags |> Flags.getWaitingForInputRegister of
        Just registerX ->
            let
                newFlags =
                    model
                        |> Model.getFlags
                        |> Flags.setWaitingForInputRegister Nothing

                newRegisters =
                    model
                        |> Model.getRegisters
                        |> Registers.setDataRegister registerX (KeyCode.nibbleValue keyCode)
            in
            model
                |> Model.setFlags newFlags
                |> Model.setRegisters newRegisters
                |> noCmd

        _ ->
            model
                |> noCmd


delayTick : Model -> ( Model, Cmd Msg )
delayTick model =
    let
        ( ( newRegisters, newTimers ), cmd ) =
            Timers.tick
                (model |> Model.getRegisters)
                (model |> Model.getTimers)
    in
    ( model
        |> Model.setRegisters newRegisters
        |> Model.setTimers newTimers
    , cmd
    )


clockTick : Model -> ( Model, Cmd Msg )
clockTick model =
    let
        flags =
            model |> Model.getFlags

        running =
            flags |> Flags.isRunning

        waitingForInput =
            flags |> Flags.isWaitingForInput

        speed =
            2
    in
    if running == True && waitingForInput == False then
        model |> FetchDecodeExecuteLoop.tick speed

    else
        ( model, Cmd.none )


selectGame : String -> Model -> ( Model, Cmd Msg )
selectGame gameName model =
    let
        selectedGame =
            List.find (.name >> (==) gameName) model.games
    in
    ( Model.initModel
        |> Model.setSelectedGame selectedGame
    , loadGame gameName
    )


port loadGame : String -> Cmd msg


reloadGame : Model -> ( Model, Cmd Msg )
reloadGame model =
    case model |> Model.getSelectedGame of
        Just game ->
            let
                freshModel =
                    Model.initModel

                ( newModel, cmd ) =
                    selectGame game.name freshModel
            in
            ( newModel
            , Cmd.batch
                [ freshModel |> Model.getDisplay |> Display.drawDisplay
                , cmd
                ]
            )

        Nothing ->
            model |> noCmd


readProgram : Array Value8Bit -> Model -> ( Model, Cmd Msg )
readProgram programBytes model =
    let
        programStart =
            512

        newMemory =
            List.indexedFoldl
                (\idx -> Memory.setCell (programStart + idx))
                (model |> Model.getMemory)
                (programBytes |> Array.toList)

        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setAddressRegister 0
                |> Registers.setProgramCounter programStart

        newFlags =
            model |> Model.getFlags |> Flags.setRunning True
    in
    model
        |> Model.setMemory newMemory
        |> Model.setRegisters newRegisters
        |> Model.setFlags newFlags
        |> noCmd


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        KeyDown maybeKeyCode ->
            model |> addKeyCode maybeKeyCode

        KeyUp maybeKeyCode ->
            model |> removeKeyCode maybeKeyCode

        KeyPress keyCode ->
            model |> noCmd

        DelayTick ->
            model |> delayTick

        ClockTick _ ->
            model |> clockTick

        SelectGame gameName ->
            model |> selectGame gameName

        ReloadGame ->
            model |> reloadGame

        LoadedGame gameBytes ->
            model |> readProgram gameBytes
