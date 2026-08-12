import os
from functools import wraps

from flask import jsonify, request


def require_token(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        expected = os.environ["API_TOKEN"]
        header = request.headers.get("Authorization", "")
        token = header.removeprefix("Bearer ") if header.startswith("Bearer ") else None
        if token != expected:
            return jsonify({"error": "unauthorized"}), 401
        return view(*args, **kwargs)

    return wrapped
