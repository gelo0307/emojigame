module RoomId exposing (..)

import Json.Decode
import Random


type RoomId
    = RoomId String


roomIdDecoder =
    Json.Decode.string |> Json.Decode.map RoomId


generator : Random.Generator RoomId
generator =
    Random.int 1000 Random.maxInt |> Random.map (String.fromInt >> RoomId)
