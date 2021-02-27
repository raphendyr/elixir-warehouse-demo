import json
import os.path
from flask import Flask, jsonify, safe_join, send_from_directory
from time import sleep
from random import random

api = Flask(__name__)
api.env = "development"
api.debug = True
FILES = os.path.dirname(__file__)

@api.route('/', methods=['GET'])
def index():
    return jsonify([
        {'url': '/v2/products/{category}'},
        {'url': '/v2/availability/{manufacturer}'},
    ])

@api.route('/v2/products/<category>', methods=['GET'])
def products(category):
    if random() > 0.9:
        with open(safe_join(FILES, f'products-{category}.json')) as f:
            data = json.load(f)
        return jsonify(data[:5])
    return send_from_directory(FILES, filename=f'products-{category}.json')

@api.route('/v2/availability/<manufacturer>', methods=['GET'])
def availability(manufacturer):
    return send_from_directory(FILES, filename=f'availability-{manufacturer}.json')

def before():
    val = random()
    if val > 0.9:
        return "random internal error", 500
    if val > 0.7:
        return "random error", 400
api.before_request(before)

def after_delay(response):
    if random() > 0.8:
        time = 20.
    else:
        time = 2. + 2.*random()
    api.logger.info("sleeping %.2f seconds", time)
    sleep(time)
    return response
api.after_request(after_delay)

if __name__ == '__main__':
    api.run(threaded=True)
