import pytest
import app as app_module

@pytest.fixture()
def app():
    yield app_module.app


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def runner(app):
    return app.test_cli_runner()

def test_unauth_profile(client):
    response = client.get("/profile")
    assert response.status_code == 401

def test_unauth_join_game(client):
    response = client.post("/joinGame", json={"game_id": "0"})
    assert response.status_code == 401

def test_unauth_leave_game(client):
    response = client.post("/leaveGame")
    assert response.status_code == 401

def test_unauth_get_game(client):
    response = client.get("/getGame", query_string={"game_id": "0"})
    assert response.status_code == 401