import database

from accounts import Account
from game_types import GameType
from player_roles import PlayerRole


class GameInstance:
    def __init__(self, game_id: str, player_roles: dict[Account, PlayerRole], game_type: GameType, player_points: dict[Account, int], current_turn: int, ball_positions: dict[int, tuple[float, float]], ball_rotations: dict[int, tuple[float, float]]):
        self.game_id: str = game_id
        self.player_roles: dict[Account, PlayerRole] = player_roles
        self.game_type: GameType = game_type
        self.player_points: dict[Account, int] = player_points
        self.current_turn = current_turn
        self.ball_positions: dict[int, tuple[float, float]] = ball_positions
        self.ball_rotations: dict[int, tuple[float, float]] = ball_rotations

def update_game_state(game_state: GameInstance):
    games_collection = database.db['games']
    game = games_collection.find_one({'game_id': game_state.game_id})
    if game is None:
        games_collection.insert_one(game_state.__dict__)
    else:
        games_collection.update_one({'game_id': game_state.game_id}, {'$set': game_state.__dict__})
