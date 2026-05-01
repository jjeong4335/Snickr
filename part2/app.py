"""
auth.py — Authentication Blueprint

Handles all user identity operations:
  - /register  : create a new account
  - /login     : authenticate and start a session
  - /logout    : clear the session
  - /profile   : view and update nickname

Security:
  - Passwords stored as SHA-256 hashes, never plaintext
  - All DB queries use parameterized statements (%s) to prevent SQL injection
  - Jinja2 auto-escaping prevents XSS in all rendered templates
"""

import hashlib
from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from db import get_conn
from utils import login_required

auth = Blueprint("auth", __name__)


def hash_password(password):
    """
    Return SHA-256 hex digest of the plaintext password.
    Used both when storing a new password and verifying login.
    Note: production systems should use bcrypt/argon2 with per-user salts.
    """
    return hashlib.sha256(password.encode()).hexdigest()


@auth.route("/register", methods=["GET", "POST"])
def register():
    """
    GET  — render the registration form.
    POST — insert a new user row and start a session.

    UNIQUE constraints on users.email and users.username enforce uniqueness at DB level.
    On duplicate: psycopg2 raises IntegrityError → rollback → flash error.
    """
    if request.method == "POST":
        email    = request.form["email"].strip()
        username = request.form["username"].strip()
        nickname = request.form["nickname"].strip()
        password = request.form["password"]

        conn = get_conn()
        try:
            cur = conn.cursor()
            # Parameterized INSERT — user input passed as tuple, never concatenated into SQL.
            # RETURNING gives us the new user_id without a second SELECT.
            cur.execute(
                """
                INSERT INTO users (email, username, nickname, password_hash)
                VALUES (%s, %s, %s, %s)
                RETURNING user_id
                """,
                (email, username, nickname, hash_password(password))
            )
            user_id = cur.fetchone()[0]
            conn.commit()

            # Store identity in signed session cookie.
            # user_id is the primary key used for all subsequent authorization checks.
            session["user_id"]  = user_id
            session["username"] = username
            flash("Welcome to Snickr!")
            return redirect(url_for("workspace.list_workspaces"))
        except Exception:
            conn.rollback()
            flash("Email or username already taken.")
        finally:
            conn.close()

    return render_template("auth/register.html")


@auth.route("/login", methods=["GET", "POST"])
def login():
    """
    GET  — render the login form.
    POST — verify credentials and start a session.

    We hash the submitted password and compare to the stored hash.
    Generic error message used to prevent username enumeration.
    """
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]

        conn = get_conn()
        try:
            cur = conn.cursor()
            # Compare submitted hash against stored hash — parameterized query.
            cur.execute(
                "SELECT user_id, username FROM users WHERE username = %s AND password_hash = %s",
                (username, hash_password(password))
            )
            row = cur.fetchone()
        finally:
            conn.close()

        if row:
            # Valid credentials — store identity in session.
            session["user_id"]  = row[0]
            session["username"] = row[1]
            return redirect(url_for("workspace.list_workspaces"))
        else:
            # Generic error: do not reveal which field was wrong.
            flash("Invalid username or password.")

    return render_template("auth/login.html")


@auth.route("/logout", methods=["POST"])
def logout():
    """
    Clear the entire session (removes user_id, username, and any other data).
    Uses POST to prevent logout via crafted GET link (CSRF consideration).
    """
    session.clear()
    return redirect(url_for("auth.login"))


@auth.route("/profile", methods=["GET", "POST"])
@login_required
def profile():
    """
    GET  — display current user's profile (email, username, nickname, join date).
    POST — update nickname only.

    Email and username are immutable after registration to avoid breaking
    foreign key references and invitation lookups.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()
        if request.method == "POST":
            nickname = request.form["nickname"].strip()
            cur.execute(
                "UPDATE users SET nickname = %s WHERE user_id = %s",
                (nickname, user_id)
            )
            conn.commit()
            flash("Profile updated.")

        # Fetch current profile to pre-populate the form.
        cur.execute(
            "SELECT email, username, nickname, created_at FROM users WHERE user_id = %s",
            (user_id,)
        )
        user = cur.fetchone()
    finally:
        conn.close()

    return render_template("auth/profile.html", user=user)