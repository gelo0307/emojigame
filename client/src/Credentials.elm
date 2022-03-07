module Credentials exposing (..)

import Game exposing (PlayerName(..))
import Json.Decode exposing (string, succeed)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import RoomId exposing (RoomId(..))


type alias Credentials =
    { playerName : Game.PlayerName
    , roomId : RoomId
    , secret : Secret
    }


type Secret
    = Secret String


decoder : Json.Decode.Decoder Credentials
decoder =
    succeed Credentials
        |> required "playerName" Game.playerNameDecoder
        |> required "roomId" RoomId.roomIdDecoder
        |> required "secret" secretDecoder


secretDecoder =
    string |> Json.Decode.map Secret


encoder : Credentials -> Encode.Value
encoder credentials =
    let
        (RoomId roomId) =
            credentials.roomId

        (PlayerName playerName) =
            credentials.playerName

        (Secret secret) =
            credentials.secret
    in
    Encode.object
        [ ( "roomId", Encode.string roomId )
        , ( "playerName", Encode.string playerName )
        , ( "secret", Encode.string secret )
        ]
