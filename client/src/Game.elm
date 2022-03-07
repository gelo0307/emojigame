module Game exposing (Game, Player, PlayerName(..), Turn, gameDecoder, playerNameDecoder)

import AssocList
import Dict
import Json.Decode exposing (Decoder, andThen, bool, decodeString, dict, errorToString, fail, field, int, list, map, maybe, oneOf, string, succeed)
import Json.Decode.Pipeline exposing (required)
import List.Nonempty as NE exposing (Nonempty)
import RoomId exposing (RoomId)


type alias Game =
    { players : List Player
    , id : RoomId
    , turns : Nonempty Turn
    }


type alias Player =
    { name : PlayerName
    , points : Int
    , active : Bool
    }


type alias Turn =
    { phrase : String
    , submissions : AssocList.Dict PlayerName String
    , guesser : PlayerName
    , submissionsComplete : Bool
    , bestSubmissionPlayerName : Maybe PlayerName
    }


type PlayerName
    = PlayerName String


gameDecoder : Decoder Game
gameDecoder =
    succeed Game
        |> required "players" (list playerDecoder)
        |> required "id" RoomId.roomIdDecoder
        |> required "turns" (nonemptyListDecoder turnDecoder)


nonemptyListDecoder : Decoder a -> Decoder (Nonempty a)
nonemptyListDecoder value =
    let
        fn =
            \l ->
                case NE.fromList l of
                    Nothing ->
                        fail "list not expected to be empty."

                    Just neList ->
                        succeed neList
    in
    list value |> andThen fn


playerDecoder : Decoder Player
playerDecoder =
    succeed Player
        |> required "name" playerNameDecoder
        |> required "points" int
        |> required "active" bool


turnDecoder : Decoder Turn
turnDecoder =
    succeed Turn
        |> required "phrase" string
        |> required "submissions" (map mapDict (dict string))
        |> required "guesser" playerNameDecoder
        |> required "submissionsComplete" bool
        |> required "bestSubmissionPlayerName" (maybe playerNameDecoder)


mapDict : Dict.Dict String String -> AssocList.Dict PlayerName String
mapDict =
    Dict.toList >> List.map (\( k, v ) -> ( PlayerName k, v )) >> AssocList.fromList


playerNameDecoder =
    string |> Json.Decode.map PlayerName
