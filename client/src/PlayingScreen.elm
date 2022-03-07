module PlayingScreen exposing (..)

import AssocList as Dict
import Credentials exposing (Credentials)
import EmojiPicker.EmojiPicker as EmojiPicker
import Game exposing (Game, Player, PlayerName(..), Turn)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import List.Nonempty as NE


type alias Model =
    { phase : PlayingPhase
    , emojiPicker : EmojiPicker.Model
    , game : Game
    , credentials : Credentials
    , link : String
    }


type Msg
    = UpdateGame Game
    | UpdateSubmission String
    | Submit
    | FinishTurn FinishingVote
    | EmojiMsg EmojiPicker.Msg
    | KickPlayer Game.Player
    | KickPlayerConfirm Bool
    | SkipTurn


type FinishingVote
    = Nope
    | Best String


type PlayingPhase
    = Wait
    | Invite
    | Write String
    | Submissions
    | Guess
    | ConfirmKick Game.Player


init : Credentials -> Game -> String -> Model
init credentials game link =
    { phase = currentScreen Wait game credentials
    , emojiPicker = initEmojiPicker
    , game = game
    , credentials = credentials
    , link = link
    }


initEmojiPicker =
    EmojiPicker.init
        { offsetX = 0 -- horizontal offset
        , offsetY = 0 -- vertical offset
        , closeOnSelect = False -- close after clicking an emoji
        }


update : Model -> Msg -> ( Model, Cmd Msg, Maybe WsCmd )
update model msg =
    case ( msg, model.phase ) of
        ( UpdateGame game, _ ) ->
            ( updateGame model game, Cmd.none, Nothing )

        ( UpdateSubmission submission, Write _ ) ->
            ( { model | phase = Write submission }, Cmd.none, Nothing )

        ( Submit, Write submission ) ->
            ( { model | phase = Wait }, Cmd.none, sendMessage ("submit " ++ submission) )

        ( FinishTurn finishingVote, Guess ) ->
            let
                args =
                    case finishingVote of
                        Nope ->
                            ""

                        Best playerName ->
                            " " ++ playerName
            in
            ( model, Cmd.none, sendMessage ("finish" ++ args) )

        ( EmojiMsg subMsg, phase ) ->
            case subMsg of
                EmojiPicker.Select s ->
                    case phase of
                        Write submission ->
                            ( { model | phase = Write <| submission ++ s }, Cmd.none, Nothing )

                        _ ->
                            ( model, Cmd.none, Nothing )

                EmojiPicker.Toggle ->
                    ( model, Cmd.none, Nothing )

                _ ->
                    let
                        ( m, c ) =
                            EmojiPicker.update subMsg model.emojiPicker
                    in
                    ( { model | emojiPicker = m }, Cmd.map EmojiMsg c, Nothing )

        ( KickPlayer player, _ ) ->
            ( { model | phase = ConfirmKick player }, Cmd.none, Nothing )

        ( KickPlayerConfirm confirm, ConfirmKick player ) ->
            let
                (PlayerName playerName) =
                    player.name
            in
            ( { model | phase = currentScreen model.phase model.game model.credentials }
            , Cmd.none
            , if confirm then
                sendMessage <| "kick " ++ playerName

              else
                Nothing
            )

        ( SkipTurn, _ ) ->
            ( model, Cmd.none, sendMessage "skip" )

        ( _, _ ) ->
            ( model, Cmd.none, Nothing )


type WsCmd
    = WsCmd String


sendMessage : String -> Maybe WsCmd
sendMessage =
    Just << WsCmd


updateGame : Model -> Game -> Model
updateGame model game =
    { model
        | phase = Debug.log "phase: " <| currentScreen model.phase game model.credentials
        , game = game
    }


currentScreen : PlayingPhase -> Game -> Credentials -> PlayingPhase
currentScreen oldPhase game credentials =
    if List.length game.players < 2 then
        Invite

    else if iAmTheGuesser game credentials then
        if (currentTurn game).submissionsComplete then
            Guess

        else
            Wait

    else if (currentTurn game).submissionsComplete then
        Submissions

    else if hasSubmittedForCurrentTurn game credentials then
        Wait

    else
        case oldPhase of
            Write _ ->
                oldPhase

            _ ->
                Write ""


viewPlaying : Model -> Html Msg
viewPlaying model =
    div
        ([ id "room" ]
            ++ (case model.phase of
                    Write _ ->
                        [ class "write-mode" ]

                    _ ->
                        []
               )
        )
        [ div [ id "left-col" ]
            [ viewPlayerList model
            , viewInfoDisplay model.game
            ]
        , div [ id "main-window" ] [ viewMainWindow model ]
        , div [ id "emoji-picker", style "position" "relative" ] [ viewEmojiPicker model.emojiPicker ]
        ]


viewMainWindow : Model -> Html Msg
viewMainWindow model =
    case model.phase of
        Invite ->
            viewInviteOtherPlayers model.link

        Wait ->
            viewWaitForSubmissions model.game

        Write submission ->
            viewSubmissionForm model submission

        Submissions ->
            viewSubmissions (currentTurn model.game)

        Guess ->
            viewSubmissionsForGuesser (currentTurn model.game)

        ConfirmKick player ->
            viewKickConfirm player


viewKickConfirm : Player -> Html Msg
viewKickConfirm player =
    let
        (Game.PlayerName playerName) =
            player.name
    in
    div [ id "kick-confirm" ]
        [ div [] [ text <| "Do you want to throw " ++ playerName ++ " out of the game?" ]
        , div []
            [ button [ onClick <| KickPlayerConfirm True ] [ text "Yes" ]
            , button [ onClick <| KickPlayerConfirm False ] [ text "No" ]
            ]
        ]


viewInfoDisplay : Game -> Html Msg
viewInfoDisplay game =
    div [ id "info-display" ]
        [ div []
            [ text <| "Turn " ++ (String.fromInt <| NE.length game.turns)
            , button [ onClick SkipTurn ] [ text "Skip" ]
            ]

        --, div [] [ text game.name ] --todo show url?
        ]


viewPlayerList : Model -> Html Msg
viewPlayerList model =
    div [ id "player-list" ]
        [ ul []
            (List.map (viewPlayer model) model.game.players)
        ]


viewPlayer : Model -> Player -> Html Msg
viewPlayer model player =
    let
        (Game.PlayerName playerName) =
            player.name
    in
    li
        ((if player.name == model.credentials.playerName then
            [ class "player-self" ]

          else
            []
         )
            ++ [ onClick <| KickPlayer player ]
        )
        [ div [ id "player-icon1" ]
            [ text
                (if isTheGuesser model.game player then
                    "🕵️\u{200D}♂️"

                 else if not <| playerHasSubmitted model.game player then
                    "⏳"

                 else
                    ""
                )
            ]
        , div
            ([ id "player-name" ]
                ++ (if player.active then
                        []

                    else
                        [ class "inactive" ]
                   )
            )
            [ text playerName ]
        , div [ id "player-icon2" ]
            [ text <|
                if playerGotPointLastTurn model.game player then
                    "\u{1F947}"

                else if not player.active then
                    "😴"

                else
                    ""
            ]
        , div [ id "player-points" ] [ text <| String.fromInt player.points ]
        ]


isTheGuesser : Game -> Player -> Bool
isTheGuesser game player =
    (currentTurn game).guesser == player.name


playerHasSubmitted : Game -> Player -> Bool
playerHasSubmitted game player =
    List.member player.name <| Dict.keys <| (currentTurn game).submissions


playerGotPointLastTurn : Game -> Player -> Bool
playerGotPointLastTurn game player =
    case List.head <| NE.tail game.turns of
        Nothing ->
            False

        Just turn ->
            case turn.bestSubmissionPlayerName of
                Nothing ->
                    False

                Just playerName ->
                    playerName == player.name


currentTurn : Game -> Turn
currentTurn game =
    NE.head game.turns


viewSubmissions : Turn -> Html Msg
viewSubmissions turn =
    let
        (PlayerName guesserName) =
            turn.guesser
    in
    div [ id "submission-list" ]
        [ div [] [ text turn.phrase ]
        , ul [] (List.map (\s -> li [] [ text s ]) (Dict.values turn.submissions))
        , div [] [ text <| "Wait for " ++ guesserName ++ " to guess." ]
        ]


viewSubmissionsForGuesser : Turn -> Html Msg
viewSubmissionsForGuesser turn =
    div [ id "submission-list" ]
        [ viewVotingButtons turn
        ]


viewVotingButtons : Turn -> Html Msg
viewVotingButtons turn =
    div [ id "voting-buttons" ]
        [ ul [] (List.map (\( PlayerName k, v ) -> li [ onClick <| FinishTurn (Best k) ] [ text v ]) (Dict.toList turn.submissions))
        , button [ id "vote-nope", onClick (FinishTurn Nope) ] [ text "\u{1F937}" ]
        , div [ id "vote-help" ] [ text "Did you get it? Talk to the other players. Then choose who did the best job or click \u{1F937} if you didn't guess it right." ]
        ]


viewSubmissionForm : Model -> String -> Html Msg
viewSubmissionForm model submission =
    div [ id "submission-form-container" ]
        [ viewPhrase <| currentTurn model.game
        , div [ id "submission-form" ]
            [ input [ onInput UpdateSubmission, placeholder "My Submission", value submission ] []
            , button [ onClick Submit ] [ text "Submit" ]
            ]
        ]


hasSubmittedForCurrentTurn : Game -> Credentials -> Bool
hasSubmittedForCurrentTurn game credentials =
    List.member credentials.playerName (Dict.keys (currentTurn game).submissions)


viewWaitForSubmissions : Game -> Html Msg
viewWaitForSubmissions _ =
    div [ id "wait-for-submissions" ] [ text "Waiting for the other players" ]


viewPhrase : Turn -> Html Msg
viewPhrase turn =
    div [ id "phrase" ] [ text turn.phrase ]


viewEmojiPicker : EmojiPicker.Model -> Html Msg
viewEmojiPicker model =
    Html.map EmojiMsg <| EmojiPicker.view model


iAmTheGuesser : Game -> Credentials -> Bool
iAmTheGuesser game credentials =
    (currentTurn game).guesser == credentials.playerName


viewInviteOtherPlayers : String -> Html Msg
viewInviteOtherPlayers link =
    div [ id "invite-players" ]
        [ div [] [ text "Send your friends this link to invite them to the game:" ]
        , div [ id "invite-link" ] [ text link ]
        ]
