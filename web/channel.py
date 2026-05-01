"""
channel.py — Channel Blueprint

Handles all channel-level operations:
  - /workspace/<ws_id>/channel/create           : create a public or private channel
  - /workspace/<ws_id>/channel/direct           : open or create a direct message channel
  - /channel/<ch_id>/join                       : join a public channel
  - /channel/<ch_id>/invite                     : invite a workspace member to a channel
  - /channel/<ch_id>/invitation/<inv_id>/accept : accept a channel invitation
  - /channel/<ch_id>/invitation/<inv_id>/decline: decline a channel invitation

Channel types:
  - public  : any workspace member can join freely
  - private : only invited users can join; invisible to non-members
  - direct  : exactly two users; canonical name is dm:<user1>-<user2> (alphabetical order)

Access control:
  - Creating a channel requires workspace membership (enforced via EXISTS in the INSERT CTE).
  - Inviting to a channel requires being a channel member.
  - Joining is only allowed for public channels (type verified server-side).
"""

from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from db import get_conn
from utils import login_required

channel = Blueprint("channel", __name__)


@channel.route("/workspace/<int:ws_id>/channel/create", methods=["GET", "POST"])
@login_required
def create(ws_id):
    """
    GET  — render the channel creation form.
    POST — create a new public or private channel and auto-join the creator.

    Authorization is enforced inside the SQL CTE using WHERE EXISTS, making the
    membership check and the INSERT atomic. If the user is not a workspace member,
    the CTE returns zero rows and nothing is inserted — no race condition possible.

    The creator is automatically added to channel_members so they can immediately
    post and invite others to the channel they just created.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    ws      = None
    try:
        cur = conn.cursor()

        # Verify workspace membership before rendering the form (GET).
        # Prevents non-members from even seeing the channel creation form.
        cur.execute(
            "SELECT 1 FROM workspace_members WHERE workspace_id=%s AND user_id=%s",
            (ws_id, user_id)
        )
        if not cur.fetchone():
            flash("Not a workspace member.")
            return redirect(url_for("workspace.list_workspaces"))

        cur.execute("SELECT name FROM workspaces WHERE workspace_id=%s", (ws_id,))
        ws = cur.fetchone()

        if request.method == "POST":
            name    = request.form["name"].strip()
            ch_type = request.form["type"]

            # Sanitize type — only 'public' and 'private' are valid here.
            # 'direct' channels are created through a dedicated route.
            if ch_type not in ("public", "private"):
                ch_type = "public"

            # CTE-based atomic insert:
            #   Step 1: INSERT channel only if the user is a workspace member (WHERE EXISTS).
            #   Step 2: INSERT creator into channel_members using the returned channel_id.
            # This ensures we never create a channel without a first member.
            cur.execute(
                """
                WITH new_ch AS (
                    INSERT INTO channels (workspace_id, name, type, created_by)
                    VALUES (%s, %s, %s, %s)
                    RETURNING channel_id
                )
                INSERT INTO channel_members (channel_id, user_id)
                SELECT channel_id, %s FROM new_ch
                RETURNING channel_id
                """,
                (ws_id, name, ch_type, user_id, user_id)
            )
            ch_id = cur.fetchone()[0]
            conn.commit()
            return redirect(url_for("message.detail", ch_id=ch_id))

    except Exception:
        # UNIQUE constraint on (workspace_id, name) triggers this if name already taken.
        conn.rollback()
        flash("Channel name already exists in this workspace.")
    finally:
        conn.close()

    return render_template("channel/create.html", ws_id=ws_id, ws=ws)


@channel.route("/workspace/<int:ws_id>/channel/direct", methods=["GET", "POST"])
@login_required
def create_direct(ws_id):
    """
    GET  — render a form listing workspace members the user can DM.
    POST — open or create a direct message channel between current user and target.

    DM naming convention:
      Usernames are sorted alphabetically and joined as 'dm:<user1>-<user2>'.
      This canonical name ensures the same DM is unique regardless of who initiates it.
      If the DM already exists, redirect to it instead of creating a duplicate.

    Both users are added to channel_members in the same transaction so neither
    can be left out if one insert fails.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    try:
        cur = conn.cursor()

        # Verify the initiating user is a workspace member.
        cur.execute(
            "SELECT 1 FROM workspace_members WHERE workspace_id=%s AND user_id=%s",
            (ws_id, user_id)
        )
        if not cur.fetchone():
            flash("Not a workspace member.")
            return redirect(url_for("workspace.list_workspaces"))

        if request.method == "POST":
            target_username = request.form["username"].strip()

            # Look up the target user by username.
            cur.execute("SELECT user_id, username FROM users WHERE username=%s", (target_username,))
            target = cur.fetchone()
            if not target:
                flash("User not found.")
                return redirect(request.url)

            target_id = target[0]

            # Ensure the target is also a workspace member.
            # DMs are only possible between users in the same workspace.
            cur.execute(
                "SELECT 1 FROM workspace_members WHERE workspace_id=%s AND user_id=%s",
                (ws_id, target_id)
            )
            if not cur.fetchone():
                flash("That user is not in this workspace.")
                return redirect(request.url)

            # Build canonical DM name by sorting usernames alphabetically.
            # e.g., alice+carol → dm:alice-carol (always, regardless of who initiated)
            names   = sorted([session["username"], target_username])
            dm_name = f"dm:{names[0]}-{names[1]}"

            # Check if DM already exists — redirect to it if so.
            cur.execute(
                "SELECT channel_id FROM channels WHERE workspace_id=%s AND name=%s",
                (ws_id, dm_name)
            )
            existing = cur.fetchone()
            if existing:
                return redirect(url_for("message.detail", ch_id=existing[0]))

            # Create the DM channel and add both users atomically.
            # Both inserts happen before commit — no window where only one user is in the channel.
            cur.execute(
                "INSERT INTO channels (workspace_id, name, type, created_by) "
                "VALUES (%s,%s,'direct',%s) RETURNING channel_id",
                (ws_id, dm_name, user_id)
            )
            ch_id = cur.fetchone()[0]
            cur.execute("INSERT INTO channel_members (channel_id, user_id) VALUES (%s,%s)", (ch_id, user_id))
            cur.execute("INSERT INTO channel_members (channel_id, user_id) VALUES (%s,%s)", (ch_id, target_id))
            conn.commit()
            return redirect(url_for("message.detail", ch_id=ch_id))

        # GET: fetch workspace members (excluding self) for the selection list.
        cur.execute(
            """
            SELECT u.username, u.nickname FROM workspace_members wm
            JOIN users u ON u.user_id = wm.user_id
            WHERE wm.workspace_id=%s AND wm.user_id != %s
            ORDER BY u.username
            """,
            (ws_id, user_id)
        )
        members = cur.fetchall()
        cur.execute("SELECT name FROM workspaces WHERE workspace_id=%s", (ws_id,))
        ws = cur.fetchone()
    finally:
        conn.close()

    return render_template("channel/direct.html", ws_id=ws_id, ws=ws, members=members)


@channel.route("/channel/<int:ch_id>/join", methods=["POST"])
@login_required
def join(ch_id):
    """
    Join a public channel.

    Channel type is re-verified server-side — never trust client-side data.
    Only public channels can be joined freely; private and direct channels require an invitation.
    ON CONFLICT DO NOTHING prevents an error on duplicate submission.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    try:
        cur = conn.cursor()
        # Re-verify channel type from the DB, not from the request.
        cur.execute("SELECT type, workspace_id FROM channels WHERE channel_id=%s", (ch_id,))
        ch = cur.fetchone()
        if ch and ch[0] == "public":
            cur.execute(
                "INSERT INTO channel_members (channel_id, user_id) VALUES (%s,%s) ON CONFLICT DO NOTHING",
                (ch_id, user_id)
            )
            conn.commit()
    finally:
        conn.close()
    return redirect(url_for("message.detail", ch_id=ch_id))


@channel.route("/channel/<int:ch_id>/invite", methods=["GET", "POST"])
@login_required
def invite(ch_id):
    """
    GET  — render invite form showing eligible workspace members.
    POST — send a channel invitation to the specified user.

    Eligibility: must be a workspace member and not already in the channel.
    Only current channel members can invite others.
    ON CONFLICT DO NOTHING prevents duplicate pending invitations
    (enforced by UNIQUE on (channel_id, invitee_id, status)).
    """
    user_id    = session["user_id"]
    conn       = get_conn()
    ch_name    = None
    ws_id      = None
    candidates = []
    try:
        cur = conn.cursor()

        # Fetch channel metadata to verify it exists and get workspace context.
        cur.execute("SELECT name, workspace_id, type FROM channels WHERE channel_id=%s", (ch_id,))
        ch = cur.fetchone()
        if not ch:
            flash("Channel not found.")
            return redirect(url_for("workspace.list_workspaces"))

        ch_name, ws_id, ch_type = ch

        # Only existing channel members can invite new members.
        cur.execute(
            "SELECT 1 FROM channel_members WHERE channel_id=%s AND user_id=%s",
            (ch_id, user_id)
        )
        if not cur.fetchone():
            flash("You are not a member of this channel.")
            return redirect(url_for("workspace.detail", ws_id=ws_id))

        if request.method == "POST":
            target_username = request.form["username"].strip()
            cur.execute("SELECT user_id FROM users WHERE username=%s", (target_username,))
            target = cur.fetchone()
            if not target:
                flash("User not found.")
            else:
                target_id = target[0]
                # UNIQUE constraint on (channel_id, invitee_id, status) prevents
                # duplicate pending invitations for the same user.
                cur.execute(
                    """
                    INSERT INTO channel_invitations (channel_id, inviter_id, invitee_id)
                    VALUES (%s, %s, %s)
                    ON CONFLICT DO NOTHING
                    """,
                    (ch_id, user_id, target_id)
                )
                conn.commit()
                flash(f"Invitation sent to {target_username}.")
            return redirect(url_for("message.detail", ch_id=ch_id))

        # GET: build candidate list — workspace members not yet in this channel,
        # excluding the inviter themselves.
        cur.execute(
            """
            SELECT u.username, u.nickname FROM workspace_members wm
            JOIN users u ON u.user_id = wm.user_id
            WHERE wm.workspace_id=%s
              AND wm.user_id != %s
              AND NOT EXISTS (
                  SELECT 1 FROM channel_members cm
                  WHERE cm.channel_id=%s AND cm.user_id=wm.user_id
              )
            ORDER BY u.username
            """,
            (ws_id, user_id, ch_id)
        )
        candidates = cur.fetchall()
    finally:
        conn.close()

    return render_template("channel/invite.html", ch_id=ch_id, ch_name=ch_name, ws_id=ws_id, candidates=candidates)


@channel.route("/channel/<int:ch_id>/invitation/<int:inv_id>/accept", methods=["POST"])
@login_required
def accept_invite(ch_id, inv_id):
    """
    Accept a pending channel invitation.

    Two steps in one transaction:
      1. Update invitation status to 'accepted' and record responded_at.
      2. Insert the user into channel_members.

    AND invitee_id = %s ensures users can only accept their own invitations.
    ON CONFLICT DO NOTHING on members insert handles duplicate submissions safely.
    Invitation row is kept for audit — never deleted.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE channel_invitations SET status='accepted', responded_at=NOW() "
            "WHERE invitation_id=%s AND invitee_id=%s",
            (inv_id, user_id)
        )
        cur.execute(
            "INSERT INTO channel_members (channel_id, user_id) VALUES (%s,%s) ON CONFLICT DO NOTHING",
            (ch_id, user_id)
        )
        conn.commit()
        cur.execute("SELECT workspace_id FROM channels WHERE channel_id=%s", (ch_id,))
        ws_id = cur.fetchone()[0]
    finally:
        conn.close()
    return redirect(url_for("workspace.detail", ws_id=ws_id))


@channel.route("/channel/<int:ch_id>/invitation/<int:inv_id>/decline", methods=["POST"])
@login_required
def decline_invite(ch_id, inv_id):
    """
    Decline a pending channel invitation.

    Updates invitation status to 'declined' and records responded_at.
    No channel_members row is created. Invitation row kept for audit.
    """
    user_id = session["user_id"]
    conn    = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE channel_invitations SET status='declined', responded_at=NOW() "
            "WHERE invitation_id=%s AND invitee_id=%s",
            (inv_id, user_id)
        )
        conn.commit()
        cur.execute("SELECT workspace_id FROM channels WHERE channel_id=%s", (ch_id,))
        ws_id = cur.fetchone()[0]
    finally:
        conn.close()
    return redirect(url_for("workspace.detail", ws_id=ws_id))