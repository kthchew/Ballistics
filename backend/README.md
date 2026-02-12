# Backend

## Accounts
An account has an email and password. A user can be in one current game at a time, and the game is not necessarily finished in one sitting.

To remember which game a player is in (even after logging out and back in), each game round is associated with a random ID. An account has a field to store the current game ID, and can be null if the player is not in a game.

## Games
A game stores the state of a round such that a game server can recover the state of the game if it is restarted. Thus, a game stores the following information:
- Game ID
- "Role" of each player (e.g. who is stripes, who is solids)
- Type of game (regular 8-ball, crazy pool, etc.)
- Points for each player
- Current turn number
- Positions of each ball (null if not on the table)
- Rotations of each ball (null if not on the table)

Game state is stored at the end of each turn, not during a turn. Therefore, at the moment game state is saved, all balls are stationary.

Some types of games store additional information.

### Crazy Pool
Crazy pool games additionally store the following:
- Position of each table-placeable powerup/obstacle (for active powerups)
- Player powerup inventories
