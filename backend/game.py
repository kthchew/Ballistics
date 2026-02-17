from bson import ObjectId

import database

from accounts import Account
from game_types import GameType
from player_roles import PlayerRole

class GameInstance:
    def __init__(self, game_id: str, player_roles: dict[ObjectId, PlayerRole], game_type: GameType, player_points: dict[ObjectId, int], current_turn: int, ball_positions: dict[int, tuple[float, float]], ball_rotations: dict[int, tuple[float, float]]):
        self.game_id: str = game_id
        self.player_roles: dict[ObjectId, PlayerRole] = player_roles
        self.game_type: GameType = game_type
        self.player_points: dict[ObjectId, int] = player_points
        self.current_turn = current_turn
        self.ball_positions: dict[int, tuple[float, float]] = ball_positions
        self.ball_rotations: dict[int, tuple[float, float]] = ball_rotations

def game_instance_to_mongo_dict(game_instance: GameInstance) -> dict:
    return {
        'game_id': game_instance.game_id,
        'player_roles': [(str(player_id), role.value) for player_id, role in game_instance.player_roles.items()],
        'game_type': game_instance.game_type.value,
        'player_points': [(str(player_id), points) for player_id, points in game_instance.player_points.items()],
        'current_turn': game_instance.current_turn,
        'ball_positions': [(str(ball_id), position) for ball_id, position in game_instance.ball_positions.items()],
        'ball_rotations': [(str(ball_id), rotation) for ball_id, rotation in game_instance.ball_rotations.items()]
    }

def mongo_dict_to_game_instance(mongo_dict: dict) -> GameInstance:
    return GameInstance(
        game_id=mongo_dict['game_id'],
        player_roles={ObjectId(player_id): PlayerRole(role) for player_id, role in mongo_dict['player_roles']},
        game_type=GameType(mongo_dict['game_type']),
        player_points={ObjectId(player_id): points for player_id, points in mongo_dict['player_points']},
        current_turn=mongo_dict['current_turn'],
        ball_positions={int(ball_id): position for ball_id, position in mongo_dict['ball_positions']},
        ball_rotations={int(ball_id): rotation for ball_id, rotation in mongo_dict['ball_rotations']}
    )

def update_game_state(game_state: GameInstance) -> bool:
    games_collection = database.db['games']
    test_state = GameInstance("123", {ObjectId(): PlayerRole.STRIPES}, GameType.EIGHT_BALL_MULTIPLAYER, {ObjectId(): 123}, 0, {0: (0.0, 0.0)}, {0: (0.0, 0.0)})
    result = games_collection.update_one(
        {'game_id': game_state.game_id},
        {'$set': game_instance_to_mongo_dict(test_state)},
        upsert=True
    )
    return result.acknowledged
