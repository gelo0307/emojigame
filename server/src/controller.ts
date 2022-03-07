import {Player, Room} from "./server";

export const controller = {
    room: (args: string[], player: Player, room: Room) => {
        if (player.room !== null) {
            player.ws.send(player.room.name);
        } else {
            player.ws.send('error You have not joined a room yet.');
        }
    }
};
