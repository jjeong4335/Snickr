"""
message.py — Message Blueprint

Handles all message-level operations:
  - /channel/<ch_id>  : read messages and post new ones
  - /search           : keyword search across accessible messages

Access control:
  - Reading and posting requires channel membership (checked via channel_members).
  - Search results are filtered by both channel and workspace membership,
    enforcing the same access rules as Query 7 from Part 1.
  - All routes require login (@login_required).
"""

from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from db import get_conn
from utils import login_required

message = Blueprint("message", __name__)


@message.route("/channel/<int:ch_id>", methods=["GET", "POST"])
@login_required
def detail(ch_id):
    """
    GET  — render the channel page with all messages in chronological order.
    POST — insert a new message from the logged-in user.

    Access control: user must be a channel_member to read or post.
    If not a member, they are redirected to the workspace detail page.

    After POST, the page redirects to itself (GET) to prevent duplicate
    message submission on browser refresh (Post/Redirect/Get pattern).

    Messages are ordered by posted_at ASC, message_id ASC.
    The message_id tiebreaker ensures consistent ordering even when two
    messages are posted within the same millisecond.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    try:
        cur = conn.cursor()

        # Fetch channel metadata to verify it exists and get workspace context.
        cur.execute(
            "SELECT name, type, workspace_id FROM channels WHERE channel_id=%s",
            (ch_id,)
        )
        ch = cur.fetchone()
        if not ch:
            flash("Channel not found.")
            return redirect(url_for("workspace.list_workspaces"))

        ch_name, ch_type, ws_id = ch

        # Access control: user must be a channel member to read or post.
        # This is checked server-side on every request — never trust the URL alone.
        cur.execute(
            "SELECT 1 FROM channel_members WHERE channel_id=%s AND user_id=%s",
            (ch_id, user_id)
        )
        if not cur.fetchone():
            flash("You are not a member of this channel.")
            return redirect(url_for("workspace.detail", ws_id=ws_id))

        if request.method == "POST":
            body = request.form["body"].strip()
            if body:
                # Parameterized INSERT — prevents SQL injection.
                # posted_at defaults to CURRENT_TIMESTAMP in the DB schema.
                cur.execute(
                    "INSERT INTO messages (channel_id, sender_id, body) VALUES (%s, %s, %s)",
                    (ch_id, user_id, body)
                )
                conn.commit()
            # Post/Redirect/Get: redirect to GET so browser refresh doesn't resubmit.
            return redirect(url_for("message.detail", ch_id=ch_id))

        # Fetch all messages in this channel in chronological order.
        # message_id ASC is the tiebreaker for messages with identical posted_at.
        cur.execute(
            """
            SELECT m.message_id, m.posted_at, u.username, u.nickname, m.body
            FROM messages m
            JOIN users u ON u.user_id = m.sender_id
            WHERE m.channel_id = %s
            ORDER BY m.posted_at ASC, m.message_id ASC
            """,
            (ch_id,)
        )
        messages = cur.fetchall()

        # Fetch workspace name for the breadcrumb link (← Workspace Name).
        cur.execute("SELECT name FROM workspaces WHERE workspace_id=%s", (ws_id,))
        ws = cur.fetchone()
    finally:
        conn.close()

    return render_template(
        "channel/detail.html",
        ch_id=ch_id, ch_name=ch_name, ch_type=ch_type,
        ws_id=ws_id, ws=ws, messages=messages
    )


@message.route("/search")
@login_required
def search():
    """
    Keyword search across all messages accessible to the logged-in user.

    Access control is enforced entirely in SQL using two EXISTS subqueries
    (same pattern as Query 7 from Part 1):
      - User must be a member of the channel where the message was posted.
      - User must be a member of the workspace that contains the channel.
    This means private channel messages and messages from workspaces the user
    has left are automatically excluded from results.

    ILIKE is used for case-insensitive matching (e.g., 'Perpendicular' matches
    'perpendicular'). Results are ordered newest first for relevance.

    The keyword is passed as a GET parameter (?q=...) so search result pages
    can be bookmarked and shared.
    """
    user_id = session["user_id"]
    keyword = request.args.get("q", "").strip()
    results = []

    if keyword:
        conn = get_conn()
        try:
            cur = conn.cursor()
            # Access-controlled keyword search:
            #   ILIKE '%keyword%' — case-insensitive substring match
            #   EXISTS (channel_members) — user must be in the channel
            #   EXISTS (workspace_members) — user must be in the workspace
            # Both EXISTS checks use the logged-in user_id from the session.
            cur.execute(
                """
                SELECT m.message_id, m.posted_at,
                       w.name AS workspace_name,
                       c.name AS channel_name, c.type AS channel_type,
                       sender.username, m.body
                FROM messages m
                JOIN channels   c      ON c.channel_id   = m.channel_id
                JOIN workspaces w      ON w.workspace_id = c.workspace_id
                JOIN users      sender ON sender.user_id = m.sender_id
                WHERE m.body ILIKE %s
                  AND EXISTS (
                      SELECT 1 FROM channel_members cm
                      WHERE cm.channel_id = c.channel_id AND cm.user_id = %s
                  )
                  AND EXISTS (
                      SELECT 1 FROM workspace_members wm
                      WHERE wm.workspace_id = w.workspace_id AND wm.user_id = %s
                  )
                ORDER BY m.posted_at DESC
                """,
                (f"%{keyword}%", user_id, user_id)
            )
            results = cur.fetchall()
        finally:
            conn.close()

    return render_template("search.html", keyword=keyword, results=results)