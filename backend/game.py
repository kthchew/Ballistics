from accounts import Account
from game_types import GameType
from player_roles import PlayerRole


class GameInstance:
    def __init__(self, game_id: str):
        self.game_id: str = game_id
        self.player_roles: dict[Account, PlayerRole] = {}
        self.game_type: GameType = GameType.EIGHT_BALL_MULTIPLAYER
        self.player_points: dict[Account, int] = {}
        self.current_turn = 0
        self.ball_positions: dict[int, tuple[float, float]] = {}
        self.ball_rotations: dict[int, tuple[float, float]] = {}
