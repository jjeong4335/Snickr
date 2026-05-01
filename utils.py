"""
utils.py — Shared Utilities

Contains helper decorators and functions used across multiple blueprints.
"""

from functools import wraps
from flask import session, redirect, url_for, flash


def login_required(f):
    """
    Route decorator that enforces authentication.

    If the user is not logged in (no user_id in session), they are redirected
    to the login page with a flash message. Applied to every route that requires
    an authenticated user.

    Usage:
        @app.route("/some-page")
        @login_required
        def some_page():
            ...

    How Flask session works:
        - After login, user_id and username are stored in a signed cookie.
        - The cookie is signed with app.secret_key — users cannot tamper with it.
        - On each request, Flask decodes the cookie and populates session{}.
        - If the cookie is missing or invalid, session is empty → redirect to login.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            flash("Please log in first.")
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorated