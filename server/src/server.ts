import * as express from 'express';
import * as http from 'http';
import * as WebSocket from 'ws';
import * as fs from 'fs';
import * as path from "path";


const app = express();

app.get('/stats', (req, res) => {
    res.send('Rooms: ' + Array.from(rooms.keys()).join(', '));
});
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname + '/../../../client/public/index.html'));
});
app.get(/^\/\w+$/, (req, res) => {
    res.sendFile(path.join(__dirname + '/../../../client/public/index.html'));
});

app.use(express.static(__dirname + '/../../../client/public'));

const server = http.createServer(app);

const wss = new WebSocket.Server({ server });


const phrasesets = {
    'german': fs.readFileSync(__dirname + '/../../phrasesets/bence.txt').toString()
        .split("\n")
        .filter((v) => v.trim() !== '')
};

let playersBySocket: WeakMap<WebSocket, Player> = new Map();
let rooms: Map<string, Room> = new Map();
let lastSkip: Date = new Date();
let playersBySecret: Map<string, Player> = new Map();

export class Player {
    public ws: WebSocket;
    public name: string;
    public room: Room;
    public points: number = 0;
    public active: boolean = true;
    public ponged: boolean = true;
    public secret: string;

    constructor(name: string, ws: WebSocket, room: Room, secret: string) {
        this.name = name;
        this.ws = ws;
        this.room = room;
        this.secret = secret;
    }

    public toJson() {
        return {
            name: this.name,
            points: this.points,
            active: this.active,
        }
    }
}

export class Room {
    public readonly players: Player[] = [];
    public readonly playersByName: Map<string, Player> = new Map();
    public name: string;
    public turns: Turn[] = [];
    private phraseset: string[];

    constructor(initialPlayerName: string, initialPlayerWs: WebSocket, initialPlayerSecret: string, phraseset: string[]) {
        this.name = createUuid();
        this.join(initialPlayerName, initialPlayerWs, initialPlayerSecret);
        this.phraseset = phraseset.slice(); // slice copies the array
        this.turns.push(new Turn(this.getRandomPhrase(), this.players[0]));
        rooms.set(this.name, this);
    }


    public join(name: string, ws: WebSocket, secret: string) {
        const existingPlayer = this.playersByName.get(name);
        if ( existingPlayer ) {
                console.log('reconnecting existing player.');
                existingPlayer.ws = ws;
                existingPlayer.active = true;
                existingPlayer.ponged = true;
                playersBySocket.set(ws, existingPlayer);
        } else {
            const player = new Player(name, ws, this, secret);
            this.players.push(player);
            this.playersByName.set(name, player);
            playersBySocket.set(ws, player);
            playersBySecret.set(secret, player);
        }
        return true;
    }

    public currentTurn(): Turn {
        return this.turns[0];
    }

    private broadcast(msg: string) {
        this.players.forEach((player) => {
            if (player.ws.readyState === player.ws.OPEN) {
                player.ws.send(msg);
            }
        });
    }

    public activePlayers(): Player[] {
        return this.players.filter((player: Player) => player.active);
    }

    public broadCastState() {
        this.broadcast(JSON.stringify({ game : this.toJson() }));
    }

    public submissionsComplete(): boolean
    {
        if (this.players.length < 2) {
            return false;
        }
        return this.currentTurn().submissions.size === (this.players.length - 1);
    }

    public addSubmission(player: Player, submission: string)
    {
        this.currentTurn().submissions.set(player, submission);
        this.checkSubmissionsComplete();
        this.broadCastState();
    }

    public checkSubmissionsComplete() {
        if (this.submissionsComplete()) {
            this.currentTurn().submissionsComplete = true;
        }
    }

    public finishTurn(guessedRight: boolean, bestSubmissionPlayerName: string|null = null) {
        if (bestSubmissionPlayerName) {
            let bestSubmissionPlayer = this.playersByName.get(bestSubmissionPlayerName);
            if (bestSubmissionPlayer && this.currentTurn().submissions.has(bestSubmissionPlayer)) {
                bestSubmissionPlayer.points += 1;
                this.currentTurn().bestSubmissionPlayerName = bestSubmissionPlayerName;
            }
            this.currentTurn().guesser.points += 1;
        }
        const newTurn = new Turn(
            this.getRandomPhrase(),
            this.getPlayerAfter(this.currentTurn().guesser)
        );
        this.turns.unshift(newTurn);
    }

    private getPlayerAfter(player: Player) {
        let index = this.players.indexOf(player);
        if (this.players[index + 1] !== undefined) {
            return this.players[index + 1];
        }
        return this.players[0];
    }

    public getRandomPhrase(): string {
        if (this.phraseset.length == 0) {
            return "sorry, there are no more words left.";
        }
        const randomIndex = Math.floor(Math.random() * this.phraseset.length);
        const phrase = this.phraseset[randomIndex];
        this.phraseset.splice(randomIndex, 1);
        return phrase;
    }

    public toJson() {
        return {
            players: this.players.map((player: Player) => {
                return player.toJson();
            }),
            id: this.name,
            turns: Array.from<Turn>(this.turns).map((turn: Turn) => {
                return turn.toJson();
            })
        };
    }
}

export class Turn {
    public phrase: string;
    public submissions: Map<Player, string> = new Map();
    public submissionsComplete: boolean = false;
    public guesser: Player;
    public bestSubmissionPlayerName: string|null = null;

    constructor(phrase: string, guesser: Player) {
        this.phrase = phrase;
        this.guesser = guesser;
    }

    private submissionsByPlayerName() {
        let obj: any = {};
        this.submissions.forEach((value: string, player: Player) => {obj[player.name] = value});
        return obj;
    }

    public toJson() {
        return {
            phrase: this.phrase,
            submissions: this.submissionsByPlayerName(),
            guesser: this.guesser.name,
            submissionsComplete: this.submissionsComplete,
            bestSubmissionPlayerName: this.bestSubmissionPlayerName,
        }
    }
}

function sendError(ws: WebSocket, message: string) {
    ws.send(JSON.stringify({error: message}));
}

function sendJoinedMsg(ws: WebSocket, room: Room, secret: string) {
    ws.send(JSON.stringify({joined: {secret, game: room.toJson()}}));
}

function createUuid(): string {
    return Math.random().toString(32).substr(2);
}

wss.on('connection', (ws: WebSocket) => {

    ws.on('message', (message: string) => {

        let parts = message.split(' ');
        let cmd = parts.shift()!;


        if (cmd === 'reconnect') {
            console.log('reconnecting player');
            if (playersBySocket.has(ws)) {
                console.log('reconnect: ws already connected to a player');
                return;
            }
            let roomName = parts.shift()!;
            let playerName: string = parts.shift()!;
            let secret: string = parts.shift()!;
            const room = rooms.get(roomName);
            if (!room) {
                sendError(ws, 'Room does not exist.');
                return;
            }
            const player = room.playersByName.get(playerName);
            if (!player) {
                sendError(ws, 'Player does not exist in room.');
                return;
            }
            if (player.secret !== secret) {
                sendError(ws, 'Invalid credentials.');
                return;
            }
            player.active = true;
            player.ws = ws;
            player.ponged = true;
            playersBySocket.set(ws, player);
            player.room.checkSubmissionsComplete();
            player.room.broadCastState();
            return;
        }

        if (cmd === 'create') {
            const playerName: string = parts.shift()!;
            console.log(playerName);
            const secret = createUuid();
            const room = new Room(playerName, ws, secret, phrasesets['german']);
            sendJoinedMsg(ws, room, secret);
            return;
        }

        if (cmd === 'join') {
            let roomName = parts.shift()!;
            let playerName: string = parts.shift()!;

            let room = rooms.get(roomName);
            if (!room) {
                sendError(ws, 'Room does not exist.');
                return;
            }
            const secret = createUuid();
            if (!room.join(playerName, ws, secret)) {
                return;
            }
            sendJoinedMsg(ws, room, secret);
            room.broadCastState();
            return;
        }

        if (!playersBySocket.has(ws)) {
            sendError(ws,'No player for this connection.');
            return;
        }

        let player = playersBySocket.get(ws)!;
        if (playersBySocket.get(ws)!.room === null) {
            sendError(ws, 'Room does not exist.');
            return;
        }

        let room = player.room!;

        let currentTurn = room.currentTurn();

        if (cmd === 'phrase') {
            ws.send(currentTurn!.phrase);
        }

        if (cmd === 'submit') {
            let submission = parts.join(' ')!;
            room.addSubmission(player, submission);
            room.broadCastState();
        }

        if (cmd === 'finish') {
            let bestSubmissionPlayerName = parts.shift();
            room.finishTurn(true, bestSubmissionPlayerName);
            room.broadCastState();
        }

        if (cmd === 'kick') {
            let playerToKickName = parts.shift()!;
            let playerToKick = room.playersByName.get(playerToKickName);
            console.log('trying to kick user ' + playerToKickName);
            if (!playerToKick) {
                console.log('user does not exist');
                return;
            }
            if (room.currentTurn().guesser == playerToKick) {
                room.finishTurn(false, null);
            }
            room.playersByName.delete(playerToKickName);
            room.players.splice(room.players.indexOf(playerToKick), 1);
            playersBySocket.delete(playerToKick.ws);
            playerToKick.ws.terminate();
            room.checkSubmissionsComplete();
            room.broadCastState();
        }

        if (cmd === 'skip') {
            // throttle skips in case two people click simultaneously
            if ((new Date()).valueOf() - lastSkip.valueOf() < 10) {
                console.log('skip throttled');
                return;
            }
            // new turn but dont change guesser
            const newTurn = new Turn(
                room.getRandomPhrase(),
                room.currentTurn().guesser
            );
            room.turns.unshift(newTurn);
            room.broadCastState();
        }

    });

    ws.on('pong', () => {
        const player = playersBySocket.get(ws);
        if (!player) {
            return;
        }
        player.ponged = true;
    });

});


setInterval(() => {
    rooms.forEach((room: Room) => {
        room.activePlayers().forEach((player: Player) => {
            if (!player.ponged) {
                onWsClose(player);
            }
            player.ponged = false;
            player.ws.ping();
        });
    });
}, 5000);


function onWsClose(player: Player) {
    console.log('terminating connection for player ' + player.name + ' in room ' + player.room.name);
    playersBySocket.delete(player.ws);
    player.active = false;
    player.room.broadCastState();
    return;
}

server.listen(process.env.PORT || 8999, () => {
    console.log(`Server started on port 8999`);
});
