module VerifyExamples.FetchDecodeExecuteLoop.GetByte0 exposing (..)

-- This file got generated by [elm-verify-examples](https://github.com/stoeffel/elm-verify-examples).
-- Please don't modify this file by hand!

import Test
import Expect

import FetchDecodeExecuteLoop exposing (..)







spec0 : Test.Test
spec0 =
    Test.test "#getByte: \n\n    getByte 0x4321\n    --> 0x21" <|
        \() ->
            Expect.equal
                (
                getByte 0x4321
                )
                (
                0x21
                )