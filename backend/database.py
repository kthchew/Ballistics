import os

from pymongo import mongo_client

uri = os.environ['BALLISTIC_SERV_DB_STRING']
client = mongo_client.MongoClient(uri)
db = client['ballistic_serv']
