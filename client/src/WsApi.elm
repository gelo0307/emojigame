module WsApi exposing (..)

import Credentials exposing (Credentials)
import Game exposing (Game)
import Json.Decode as D


type Msg
    = GameState Game
    | Secret Credentials.Secret
    | Error String
    | Joined Game Credentials.Secret


decoder : D.Decoder Msg
decoder =
    D.oneOf
        [ D.field "game" Game.gameDecoder |> D.map GameState
        , D.field "error" D.string |> D.map Error
        , D.field "secret" D.string |> D.map (Secret << Credentials.Secret)
        , D.field "joined" createdDecoder |> D.map (\( g, s ) -> Joined g s)
        ]


type alias CreatedMsg =
    { game : Game.Game, secret : Credentials.Secret }


createdDecoder : D.Decoder ( Game, Credentials.Secret )
createdDecoder =
    D.map2 (\a b -> ( a, b ))
        (D.field "game" Game.gameDecoder)
        (D.field "secret" D.string |> D.map Credentials.Secret)
