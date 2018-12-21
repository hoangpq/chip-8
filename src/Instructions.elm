module Instructions exposing
    ( addToAddressRegister
    , addToRegister
    , callSubroutine
    , clearDisplay
    , displaySprite
    , hexToBitPattern
    , jumpAbsolute
    , jumpRelative
    , jumpSys
    , readRegistersFromAddressRegister
    , returnFromSubroutine
    , setAddressRegisterToConstant
    , setAddressRegisterToSpriteLocation
    , setBit
    , setDelayTimerToRegisterValue
    , setRegisterAdd
    , setRegisterAnd
    , setRegisterOr
    , setRegisterRandom
    , setRegisterShiftLeft
    , setRegisterShiftRight
    , setRegisterSub
    , setRegisterSubFlipped
    , setRegisterToConstant
    , setRegisterToDelayTimer
    , setRegisterToRegister
    , setRegisterXor
    , setSoundTimerToRegisterValue
    , skipNextIfEqualConstant
    , skipNextIfKeyNotPressed
    , skipNextIfKeyPressed
    , skipNextIfNotEqualConstant
    , skipNextIfRegistersEqual
    , skipNextIfRegistersNotEqual
    , storeBcdOfRegister
    , storeRegistersAtAddressRegister
    , waitForKeyPress
    )

{-| Instructions

All instructions are 2 bytes long and are stored most-significant-byte
first.

In memory, the first byte of each instruction should be located at an even
address.

If a program includes sprite data, it should be padded so any instructions
following it will be properly situated in RAM.

Variables used in the following instructions:

  - nnn or addr - A 12-bit value, the lowest 12 bits of the instruction
  - n or nibble - A 4-bit value, the lowest 4 bits of the instruction
  - x - A 4-bit value, the lower 4 bits of the high byte of the instruction
  - y - A 4-bit value, the upper 4 bits of the low byte of the instruction
  - kk or byte - An 8-bit value, the lowest 8 bits of the instruction

Below, all instructions are listed along with their informal descriptions
and their implementations.

-}

import Array exposing (Array)
import Bitwise
import Display
import Flags exposing (Flags)
import Keypad
import List.Extra as List
import Memory
import Model exposing (Model)
import Msg exposing (Msg(..))
import ParseInt
import Random
import Registers exposing (Registers)
import Stack
import Timers
import Types exposing (Value12Bit, Value16Bit, Value4Bit, Value8Bit)
import Utils exposing (noCmd)


{-| 0nnn - SYS addr (Jump to a machine code routine at nnn)

This instruction is only used on the old computers on which Chip-8 was
originally implemented. It is ignored by modern interpreters.

-}
jumpSys : Model -> ( Model, Cmd Msg )
jumpSys model =
    -- TODO: "jumpSys instruction is ignored"
    ( model, Cmd.none )


{-| 00E0 - CLS (Clear the display)
-}
clearDisplay : Model -> ( Model, Cmd Msg )
clearDisplay model =
    ( model |> Model.setDisplay Display.init, Cmd.none )


{-| 00EE - RET (Return from a subroutine)

The interpreter sets the program counter to the address at the top of the stack,
then decrement the stack pointer.

-}
returnFromSubroutine : Model -> ( Model, Cmd Msg )
returnFromSubroutine model =
    let
        addressAtTopOfStack =
            model
                |> Model.getStack
                |> Stack.pop
                    (Registers.getStackPointer <| Model.getRegisters <| model)
                |> Result.withDefault 0

        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setProgramCounter addressAtTopOfStack
                |> Registers.decrementStackPointer
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 1nnn - JP addr (Jump to location nnn)

The interpreter sets the program counter to nnn.

-}
jumpAbsolute : Model -> Value12Bit -> ( Model, Cmd Msg )
jumpAbsolute model location =
    let
        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setProgramCounter location
                |> Registers.decrementProgramCounter
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 2nnn - CALL addr (Call subroutine at nnn)

The interpreter increments the stack pointer, then puts the current PC on the
top of the stack. The PC is then set to nnn.

-}
callSubroutine : Model -> Value12Bit -> ( Model, Cmd Msg )
callSubroutine model location =
    let
        registers =
            model |> Model.getRegisters

        stack =
            model |> Model.getStack

        oldProgramCounter =
            registers |> Registers.getProgramCounter

        newRegisters =
            registers
                |> Registers.incrementStackPointer
                |> Registers.setProgramCounter location
                |> Registers.decrementProgramCounter

        newStack =
            stack
                |> Stack.put
                    (Registers.getStackPointer newRegisters)
                    oldProgramCounter
                |> Result.withDefault stack

        newModel =
            model |> Model.setRegisters newRegisters |> Model.setStack newStack
    in
    ( newModel, Cmd.none )


{-| 3xkk - SE Vx, byte (Skip next instruction if Vx = kk)

The interpreter compares register Vx to kk, and if they are equal,
increments the program counter by 2.

-}
skipNextIfEqualConstant : Model -> Int -> Value8Bit -> ( Model, Cmd Msg )
skipNextIfEqualConstant model register byte =
    let
        registers =
            model |> Model.getRegisters

        registerValue =
            registers
                |> Registers.getDataRegister register
                |> Result.withDefault 0

        newRegisters =
            if registerValue == byte then
                registers |> Registers.incrementProgramCounter

            else
                registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 4xkk - SNE Vx, byte (Skip next instruction if Vx != kk)

The interpreter compares register Vx to kk, and if they are not equal,
increments the program counter by 2.

-}
skipNextIfNotEqualConstant : Model -> Int -> Value8Bit -> ( Model, Cmd Msg )
skipNextIfNotEqualConstant model register value =
    let
        registers =
            model |> Model.getRegisters

        registerValue =
            registers
                |> Registers.getDataRegister register
                |> Result.withDefault 0

        newRegisters =
            if registerValue /= value then
                registers |> Registers.incrementProgramCounter

            else
                registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 5xy0 - SE Vx, Vy (Skip next instruction if Vx = Vy)

The interpreter compares register Vx to register Vy, and if they are equal,
increments the program counter by 2.

-}
skipNextIfRegistersEqual : Model -> Int -> Int -> ( Model, Cmd Msg )
skipNextIfRegistersEqual model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerValueX =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerValueY =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            if registerValueX == registerValueY then
                model
                    |> Model.getRegisters
                    |> Registers.incrementProgramCounter

            else
                model |> Model.getRegisters
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 6xkk - LD Vx, byte (Set Vx = kk)

The interpreter puts the value kk into register Vx.

-}
setRegisterToConstant : Model -> Int -> Value8Bit -> ( Model, Cmd Msg )
setRegisterToConstant model register value =
    let
        registers =
            model |> Model.getRegisters

        newRegisters =
            registers
                |> Registers.setDataRegister register value
                |> Result.withDefault registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 7xkk - ADD Vx, byte (Set Vx = Vx + kk)

Adds the value kk to the value of register Vx, then stores the result in Vx.

-}
addToRegister : Model -> Int -> Value8Bit -> ( Model, Cmd Msg )
addToRegister model register value =
    let
        registers =
            model |> Model.getRegisters

        currentRegisterValue =
            registers
                |> Registers.getDataRegister register
                |> Result.withDefault 0

        newRegisterValue =
            modBy 256 (currentRegisterValue + value)

        newRegisters =
            registers
                |> Registers.setDataRegister register newRegisterValue
                |> Result.withDefault registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 8xy0 - LD Vx, Vy (Set Vx = Vy)

Stores the value of register Vy in register Vx.

-}
setRegisterToRegister : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterToRegister model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        newRegisterXValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            registers
                |> Registers.setDataRegister registerX newRegisterXValue
                |> Result.withDefault registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| 8xy1 - OR Vx, Vy (Set Vx = Vx OR Vy)

Performs a bitwise OR on the values of Vx and Vy, then stores the result in
Vx.

-}
setRegisterOr : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterOr model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            registers
                |> Registers.setDataRegister
                    registerX
                    (Bitwise.or registerXValue registerYValue)
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy2 - AND Vx, Vy (Set Vx = Vx AND Vy)

Performs a bitwise AND on the values of Vx and Vy, then stores the result in
Vx.

-}
setRegisterAnd : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterAnd model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            registers
                |> Registers.setDataRegister
                    registerX
                    (Bitwise.and registerXValue registerYValue)
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy3 - XOR Vx, Vy (Set Vx = Vx XOR Vy)

Performs a bitwise exclusive OR on the values of Vx and Vy, then stores the
result in Vx.

-}
setRegisterXor : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterXor model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            registers
                |> Registers.setDataRegister
                    registerX
                    (Bitwise.xor registerXValue registerYValue)
                |> Result.withDefault registers

        newModel =
            model
                |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy4 - ADD Vx, Vy (Set Vx = Vx + Vy, set VF = carry)

The values of Vx and Vy are added together. If the result is greater than 8
bits (i.e., > 255,) VF is set to 1, otherwise 0. Only the lowest 8 bits of
the result are kept, and stored in Vx.

-}
setRegisterAdd : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterAdd model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        registerSum =
            registerXValue + registerYValue

        carryValue =
            if registerSum > 255 then
                1

            else
                0

        newRegisters =
            registers
                |> Registers.setDataRegister registerX (modBy 256 registerSum)
                |> Result.andThen (Registers.setDataRegister 15 carryValue)
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy5 - SUB Vx, Vy (Set Vx = Vx - Vy, set VF = NOT borrow)

If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is subtracted from Vx,
and the results stored in Vx.

-}
setRegisterSub : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterSub model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        carryValue =
            if registerXValue > registerYValue then
                1

            else
                0

        newRegisterValue =
            if registerXValue - registerYValue < 0 then
                registerXValue - registerYValue + 256

            else
                registerXValue - registerYValue

        newRegisters =
            registers
                |> Registers.setDataRegister registerX newRegisterValue
                |> Result.andThen (Registers.setDataRegister 15 carryValue)
                |> Result.withDefault registers

        newModel =
            model
                |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy6 - SHR Vx (Set Vx = Vx SHR 1)

If the least-significant bit of Vx is 1, then VF is set to 1, otherwise 0.
Then Vx is divided by 2.

-}
setRegisterShiftRight : Model -> Int -> ( Model, Cmd Msg )
setRegisterShiftRight model registerX =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        newRegisters =
            registers
                |> Registers.setDataRegister 15 (modBy 2 registerXValue)
                |> Result.andThen (Registers.setDataRegister registerX (registerXValue // 2))
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xy7 - SUBN Vx, Vy (Set Vx = Vy - Vx, set VF = NOT borrow)

If Vy > Vx, then VF is set to 1, otherwise 0. Then Vx is subtracted from Vy,
and the results stored in Vx.

-}
setRegisterSubFlipped : Model -> Int -> Int -> ( Model, Cmd Msg )
setRegisterSubFlipped model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        carryValue =
            if registerYValue > registerXValue then
                1

            else
                0

        newRegisterValue =
            if registerYValue - registerXValue < 0 then
                registerYValue - registerXValue + 256

            else
                registerYValue - registerXValue

        newRegisters =
            registers
                |> Registers.setDataRegister registerX newRegisterValue
                |> Result.andThen (Registers.setDataRegister 15 carryValue)
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 8xyE - SHL Vx (Set Vx = Vx SHL 1)

If the most-significant bit of Vx is 1, then VF is set to 1, otherwise to 0.
Then Vx is multiplied by 2.

-}
setRegisterShiftLeft : Model -> Int -> ( Model, Cmd Msg )
setRegisterShiftLeft model registerX =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        carryValue =
            Bitwise.shiftRightBy 7 registerXValue

        newRegisterValue =
            modBy 256 (registerXValue * 2)

        newRegisters =
            registers
                |> Registers.setDataRegister 15 carryValue
                |> Result.andThen (Registers.setDataRegister registerX newRegisterValue)
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| 9xy0 - SNE Vx, Vy (Skip next instruction if Vx != Vy)

The values of Vx and Vy are compared, and if they are not equal, the program
counter is increased by 2.

-}
skipNextIfRegistersNotEqual : Model -> Int -> Int -> ( Model, Cmd Msg )
skipNextIfRegistersNotEqual model registerX registerY =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        registerYValue =
            registers
                |> Registers.getDataRegister registerY
                |> Result.withDefault 0

        newRegisters =
            if registerXValue /= registerYValue then
                registers |> Registers.incrementProgramCounter

            else
                registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| Annn - LD I, addr (Set I = nnn)

The value of register I is set to nnn.

-}
setAddressRegisterToConstant : Model -> Value12Bit -> ( Model, Cmd Msg )
setAddressRegisterToConstant model location =
    let
        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setAddressRegister location
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| Bnnn - JP V0, addr (Jump to location nnn + V0)

The program counter is set to nnn plus the value of V0.

-}
jumpRelative : Model -> Value16Bit -> ( Model, Cmd Msg )
jumpRelative model location =
    let
        registers =
            model |> Model.getRegisters

        newProgramCounter =
            location + (registers |> Registers.getDataRegister 0 |> Result.withDefault 0)

        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setProgramCounter newProgramCounter
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| Cxkk - RND Vx, byte (Set Vx = random byte AND kk)

The interpreter generates a random number from 0 to 255, which is then ANDed
with the value kk. The results are stored in Vx. See instruction 8xy2 for
more information on AND.

-}
setRegisterRandom : Model -> Int -> Value8Bit -> ( Model, Cmd Msg )
setRegisterRandom model registerX value =
    let
        ( random, newSeed ) =
            model
                |> Model.getRandomSeed
                |> Random.step (Random.int 0 255)

        registers =
            model |> Model.getRegisters

        newRegisters =
            registers
                |> Registers.setDataRegister registerX (Bitwise.and random value)
                |> Result.withDefault registers
    in
    ( model
        |> Model.setRegisters newRegisters
        |> Model.setRandomSeed newSeed
    , Cmd.none
    )


{-| Dxyn - DRW Vx, Vy, nibble (Display n-byte sprite)

    Display n-byte sprite starting at memory location I at (Vx, Vy),
    set VF = collision.

    The interpreter reads n bytes from memory, starting at the address stored in
    I. These bytes are then displayed as sprites on screen at coordinates (Vx,
    Vy). Sprites are XORed onto the existing screen. If this causes any pixels
    to be erased, VF is set to 1, otherwise it is set to 0. If the sprite is
    positioned so part of it is outside the coordinates of the display, it wraps
    around to the opposite side of the screen.

-}
displaySprite : Model -> Int -> Int -> Value4Bit -> ( Model, Cmd Msg )
displaySprite model registerX registerY n =
    let
        display =
            ( 64, 32 )

        registers =
            model |> Model.getRegisters

        memory =
            model |> Model.getMemory

        addressRegister =
            registers
                |> Registers.getAddressRegister

        sprites =
            Array.toList <|
                Array.initialize
                    n
                    (\i ->
                        memory
                            |> Memory.getCell (addressRegister + i)
                            |> Result.withDefault 0
                    )

        newModel =
            List.indexedFoldl
                (\row sprite accModel ->
                    setBitsForRow
                        display
                        ( registerX, registerY )
                        row
                        (hexToBitPattern sprite)
                        accModel
                )
                (model
                    |> Model.setRegisters
                        (registers
                            |> Registers.setDataRegister 15 0
                            |> Result.withDefault registers
                        )
                )
                sprites
    in
    ( newModel, Cmd.none )


setBitsForRow : ( Int, Int ) -> ( Int, Int ) -> Int -> List Bool -> Model -> Model
setBitsForRow display registers row bits model =
    List.indexedFoldl
        (setBitForRowColumn display registers row)
        model
        bits


setBitForRowColumn : ( Int, Int ) -> ( Int, Int ) -> Int -> Int -> Bool -> Model -> Model
setBitForRowColumn ( displayWidth, displayHeight ) ( registerX, registerY ) row column bit model =
    setBit
        (calculatePosition
            (model |> Model.getRegisters)
            registerX
            column
            displayWidth
        )
        (calculatePosition
            (model |> Model.getRegisters)
            registerY
            row
            displayHeight
        )
        bit
        model


calculatePosition : Registers -> Int -> Int -> Int -> Int
calculatePosition registers register idx max =
    let
        registerValue =
            registers
                |> Registers.getDataRegister register
                |> Result.withDefault 0
    in
    modBy max (registerValue + idx)


setBit : Int -> Int -> Bool -> Model -> Model
setBit x y newBitValue model =
    let
        ( displayWidth, displayHeight ) =
            ( 64, 32 )

        registers =
            model |> Model.getRegisters

        display =
            model |> Model.getDisplay

        carry =
            registers
                |> Registers.getDataRegister 15
                |> Result.withDefault 0

        oldBitValue =
            ((display |> Display.getCell) x y).value

        newCarry =
            if carry == 0 && oldBitValue == True && newBitValue == True then
                1

            else
                carry

        newX =
            if x > displayWidth - 1 then
                x - displayWidth

            else
                x

        newY =
            if y > displayHeight - 1 then
                y - displayHeight

            else
                y

        newRegisters =
            registers
                |> Registers.setDataRegister 15 newCarry
                |> Result.withDefault registers

        newDisplay =
            display
                |> Display.setCell
                    { column = newX
                    , row = newY
                    , value = xor oldBitValue newBitValue
                    }
    in
    model
        |> Model.setRegisters newRegisters
        |> Model.setDisplay newDisplay


{-| Converts a string to its bit pattern as a list of bools

    hexToBitPattern 43
    --> [False, False, True, False, True, False, True, True]

-}
hexToBitPattern : Int -> List Bool
hexToBitPattern number =
    let
        radix =
            2

        paddingByte =
            "00000000"

        binaryString =
            paddingByte ++ ParseInt.toRadixUnsafe radix number

        trimmedString =
            binaryString |> String.dropLeft (String.length binaryString - 8)
    in
    trimmedString
        |> String.toList
        |> List.map (ParseInt.intFromChar radix)
        |> List.map (Result.toMaybe >> Maybe.withDefault 0 >> (\x -> x > 0))


{-| Ex9E - SKP Vx (Skip next instruction if key code of value Vx is pressed)

Checks the keyboard, and if the key corresponding to the value of Vx is
currently in the down position, PC is increased by 2.

-}
skipNextIfKeyPressed : Model -> Int -> ( Model, Cmd Msg )
skipNextIfKeyPressed model registerX =
    let
        registerXValue =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        keysPressed =
            model |> Model.getKeypad |> Keypad.getKeysPressed

        newRegisters =
            if List.member registerXValue keysPressed then
                model |> Model.getRegisters |> Registers.incrementProgramCounter

            else
                model |> Model.getRegisters
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| ExA1 - SKNP Vx (Skip next instruction if key code of value Vx isn't pressed)

Checks the keyboard, and if the key corresponding to the value of Vx is
currently in the up position, PC is increased by 2.

-}
skipNextIfKeyNotPressed : Model -> Int -> ( Model, Cmd Msg )
skipNextIfKeyNotPressed model registerX =
    let
        registers =
            model |> Model.getRegisters

        registerXValue =
            registers
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        keysPressed =
            model |> Model.getKeypad |> Keypad.getKeysPressed

        newRegisters =
            if not <| List.member registerXValue keysPressed then
                registers |> Registers.incrementProgramCounter

            else
                registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| Fx07 - LD Vx, DT (Set Vx = delay timer value)

The value of DT is placed into Vx.

-}
setRegisterToDelayTimer : Model -> Int -> ( Model, Cmd Msg )
setRegisterToDelayTimer model registerX =
    let
        registers =
            model |> Model.getRegisters

        delayTimer =
            registers |> Registers.getDelayTimer

        newRegisters =
            registers
                |> Registers.setDataRegister registerX delayTimer
                |> Result.withDefault registers

        newModel =
            model |> Model.setRegisters newRegisters
    in
    ( newModel, Cmd.none )


{-| Fx0A - LD Vx, K (Wait for a key press)

Wait for a key press, store the value of the key in Vx.

All execution stops until a key is pressed, then the value of that key is
stored in Vx.

-}
waitForKeyPress : Model -> Int -> ( Model, Cmd Msg )
waitForKeyPress model registerX =
    let
        newFlags =
            model
                |> Model.getFlags
                |> Flags.setWaitingForInputRegister (Just registerX)
    in
    model
        |> Model.setFlags newFlags
        |> noCmd


{-| Fx15 - LD DT, Vx (Set delay timer = Vx)

DT is set equal to the value of Vx.

-}
setDelayTimerToRegisterValue : Model -> Int -> ( Model, Cmd Msg )
setDelayTimerToRegisterValue model registerX =
    let
        registerXValue =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        ( ( newRegisters, newTimers ), cmd ) =
            Timers.startDelayTimer
                (model
                    |> Model.getRegisters
                    |> Registers.setDelayTimer registerXValue
                )
                (model |> Model.getTimers)
    in
    ( model |> Model.setTimers newTimers |> Model.setRegisters newRegisters
    , cmd
    )


{-| Fx18 - LD ST, Vx (Set sound timer = Vx)

ST is set equal to the value of Vx.

-}
setSoundTimerToRegisterValue : Model -> Value4Bit -> ( Model, Cmd Msg )
setSoundTimerToRegisterValue model registerX =
    let
        newSoundTimer =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        cmd =
            Timers.playSound newSoundTimer
    in
    ( model
    , cmd
    )


{-| Fx1E - ADD I, Vx (Set I = I + Vx)

The values of I and Vx are added, and the results are stored in I.

-}
addToAddressRegister : Model -> Value4Bit -> ( Model, Cmd Msg )
addToAddressRegister model registerX =
    let
        registerXValue =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        newAddressRegister =
            registerXValue
                + (model
                    |> Model.getRegisters
                    |> Registers.getAddressRegister
                  )

        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setAddressRegister newAddressRegister
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| Fx29 - LD F, Vx (Set I = location of sprite for digit Vx)

The value of I is set to the location for the hexadecimal sprite
corresponding to the value of Vx. See section 2.4, Display, for more
information on the Chip-8 hexadecimal font.

-}
setAddressRegisterToSpriteLocation : Model -> Value4Bit -> ( Model, Cmd Msg )
setAddressRegisterToSpriteLocation model registerX =
    let
        registerXValue =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        newRegisters =
            model
                |> Model.getRegisters
                |> Registers.setAddressRegister (registerXValue * 5)
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )


{-| Fx33 - LD B, Vx (Store BCD representation of Vx)

Store BCD representation of Vx in memory locations I, I+1, and I+2.

The interpreter takes the decimal value of Vx, and places the hundreds digit
in memory at location in I, the tens digit at location I+1, and the ones
digit at location I+2.

-}
storeBcdOfRegister : Model -> Value4Bit -> ( Model, Cmd Msg )
storeBcdOfRegister model registerX =
    let
        addressRegister =
            model
                |> Model.getRegisters
                |> Registers.getAddressRegister

        registerXValue =
            model
                |> Model.getRegisters
                |> Registers.getDataRegister registerX
                |> Result.withDefault 0

        memory =
            model |> Model.getMemory

        newMemory =
            memory
                |> Memory.setCell
                    addressRegister
                    (registerXValue // 100)
                |> Result.andThen
                    (Memory.setCell
                        (addressRegister + 1)
                        (modBy 100 registerXValue // 10)
                    )
                |> Result.andThen
                    (Memory.setCell
                        (addressRegister + 2)
                        (modBy 10 registerXValue)
                    )
                |> Result.withDefault memory
    in
    ( model |> Model.setMemory newMemory, Cmd.none )


{-| Fx55 - LD [I], Vx (Store registers V0 through Vx in memory)

Store registers V0 through Vx in memory starting at location I.

The interpreter copies the values of registers V0 through Vx into memory,
starting at the address in I.

-}
storeRegistersAtAddressRegister : Model -> Value4Bit -> ( Model, Cmd Msg )
storeRegistersAtAddressRegister model registerX =
    let
        registers =
            model |> Model.getRegisters

        addressRegister =
            registers |> Registers.getAddressRegister

        newMemory =
            List.foldl
                (\registerY accMemory ->
                    Memory.setCell (addressRegister + registerY)
                        (registers
                            |> Registers.getDataRegister registerY
                            |> Result.withDefault 0
                        )
                        accMemory
                        |> Result.withDefault accMemory
                )
                (model |> Model.getMemory)
                (List.range 0 registerX)
    in
    ( model |> Model.setMemory newMemory, Cmd.none )


{-| Fx65 - LD Vx, [I] (Read registers V0 through Vx from memory)

Read registers V0 through Vx from memory starting at location I.

The interpreter reads values from memory starting at location I into
registers V0 through Vx.

-}
readRegistersFromAddressRegister : Model -> Value4Bit -> ( Model, Cmd Msg )
readRegistersFromAddressRegister model registerX =
    let
        registers =
            model |> Model.getRegisters

        memory =
            model |> Model.getMemory

        addressRegister =
            registers |> Registers.getAddressRegister

        newRegisters =
            List.range 0 registerX
                |> List.foldl
                    (\registerY accRegisters ->
                        accRegisters
                            |> Registers.setDataRegister registerY
                                (memory
                                    |> Memory.getCell (addressRegister + registerY)
                                    |> Result.withDefault 0
                                )
                            |> Result.withDefault accRegisters
                    )
                    registers
    in
    ( model |> Model.setRegisters newRegisters, Cmd.none )
