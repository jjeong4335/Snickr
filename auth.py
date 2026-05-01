import hashlib
from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from db import get_conn
from utils import login_required

auth = Blueprint("auth", __name__)

def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

@auth.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        email    = request.form["email"].strip()
        username = request.form["username"].strip()
        nickname = request.form["nickname"].strip()
        password = request.form["password"]

        conn = get_conn()
        try:
            cur = conn.cursor()
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
            session["user_id"]  = user_id
            session["username"] = username
            flash("Welcome to Snickr!")
            return redirect(url_for("workspace.list_workspaces"))
        except Exception as e:
            conn.rollback()
            flash("Email or username already taken.")
        finally:
            conn.close()

    return render_template("auth/register.html")


@auth.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]

        conn = get_conn()
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT user_id, username FROM users WHERE username = %s AND password_hash = %s",
                (username, hash_password(password))
            )
            row = cur.fetchone()
        finally:
            conn.close()

        if row:
            session["user_id"]  = row[0]
            session["username"] = row[1]
            return redirect(url_for("workspace.list_workspaces"))
        else:
            flash("Invalid username or password.")

    return render_template("auth/login.html")


@auth.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("auth.login"))


@auth.route("/profile", methods=["GET", "POST"])
@login_required
def profile():
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

        cur.execute(
            "SELECT email, username, nickname, created_at FROM users WHERE user_id = %s",
            (user_id,)
        )
        user = cur.fetchone()
    finally:
        conn.close()

    return render_template("auth/profile.html", user=user)
