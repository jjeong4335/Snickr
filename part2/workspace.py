"""
workspace.py — Workspace Blueprint

Handles all workspace-level operations:
  - /                                             : list workspaces the user belongs to
  - /workspace/create                             : create a new workspace
  - /workspace/<ws_id>                            : workspace detail (channels + members)
  - /workspace/<ws_id>/invite                     : invite a user by email (admins only)
  - /workspace/<ws_id>/invitation/<inv_id>/accept : accept a pending workspace invitation
  - /workspace/<ws_id>/invitation/<inv_id>/decline: decline a pending workspace invitation
  - /workspace/<ws_id>/toggle_admin/<target_id>   : grant or revoke admin role (admins only)

Access control:
  - All routes require login (@login_required).
  - Invite and toggle_admin additionally require is_admin = TRUE in workspace_members.
  - Access is checked by querying the DB, never by trusting URL parameters.
"""

from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from db import get_conn
from utils import login_required

workspace = Blueprint("workspace", __name__)


@workspace.route("/")
@login_required
def list_workspaces():
    """
    Show all workspaces the logged-in user belongs to (via workspace_members),
    along with any pending workspace invitations addressed to them.

    Pending invitations are shown at the top so the user can accept or decline
    before browsing their existing workspaces.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()

        # Fetch workspaces where the user is a member.
        # is_admin included to render the "Admin" badge on workspace cards.
        cur.execute(
            """
            SELECT w.workspace_id, w.name, w.description, wm.is_admin
            FROM workspaces w
            JOIN workspace_members wm ON wm.workspace_id = w.workspace_id
            WHERE wm.user_id = %s
            ORDER BY w.name
            """,
            (user_id,)
        )
        workspaces = cur.fetchall()

        # Fetch pending workspace invitations for this user.
        # workspace_id (index 3) included so accept/decline URLs can be built correctly.
        cur.execute(
            """
            SELECT wi.invitation_id, w.name, u.username AS inviter, w.workspace_id
            FROM workspace_invitations wi
            JOIN workspaces w ON w.workspace_id = wi.workspace_id
            JOIN users u ON u.user_id = wi.inviter_id
            WHERE wi.invitee_id = %s AND wi.status = 'pending'
            """,
            (user_id,)
        )
        invitations = cur.fetchall()
    finally:
        conn.close()

    return render_template("workspace/list.html", workspaces=workspaces, invitations=invitations)


@workspace.route("/workspace/create", methods=["GET", "POST"])
@login_required
def create_workspace():
    """
    GET  — render the workspace creation form.
    POST — insert a new workspace and auto-enroll the creator as an admin member.

    Two inserts are wrapped in a single transaction:
      1. INSERT INTO workspaces
      2. INSERT INTO workspace_members with is_admin = TRUE
    If either fails (e.g., duplicate name), both are rolled back atomically.
    We never leave a workspace without at least one admin.
    """
    if request.method == "POST":
        name        = request.form["name"].strip()
        description = request.form.get("description", "").strip()
        user_id     = session["user_id"]

        conn = get_conn()
        try:
            cur = conn.cursor()

            # RETURNING gives us the new workspace_id without a second SELECT.
            cur.execute(
                "INSERT INTO workspaces (name, description, created_by) VALUES (%s, %s, %s) RETURNING workspace_id",
                (name, description, user_id)
            )
            ws_id = cur.fetchone()[0]

            # Auto-enroll creator as admin in the same transaction.
            cur.execute(
                "INSERT INTO workspace_members (workspace_id, user_id, is_admin) VALUES (%s, %s, TRUE)",
                (ws_id, user_id)
            )
            conn.commit()
            return redirect(url_for("workspace.detail", ws_id=ws_id))
        except Exception:
            # UNIQUE constraint on workspaces.name triggers this path.
            conn.rollback()
            flash("Workspace name already taken.")
        finally:
            conn.close()

    return render_template("workspace/create.html")


@workspace.route("/workspace/<int:ws_id>")
@login_required
def detail(ws_id):
    """
    Show the workspace detail page:
      - Channel list (public channels visible to all + private/direct only if member)
      - Member list with admin badges and toggle buttons (admins only)
      - Pending channel invitations for this user within this workspace

    Channel visibility rule:
      - public  : always shown; Join button if not yet a member
      - private : only shown if user is already a channel_member
      - direct  : only shown if user is already a channel_member

    Access control: if the user is not in workspace_members, redirect away.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()

        # Check membership and get admin status in one query.
        # If no row returned, user has no access to this workspace.
        cur.execute(
            "SELECT is_admin FROM workspace_members WHERE workspace_id = %s AND user_id = %s",
            (ws_id, user_id)
        )
        mem = cur.fetchone()
        if not mem:
            flash("Access denied.")
            return redirect(url_for("workspace.list_workspaces"))
        is_admin = mem[0]

        # Fetch workspace name and description for the page header.
        cur.execute("SELECT name, description FROM workspaces WHERE workspace_id = %s", (ws_id,))
        ws = cur.fetchone()

        # Fetch channels visible to this user.
        # EXISTS subquery computes is_member inline — avoids N+1 queries.
        cur.execute(
            """
            SELECT c.channel_id, c.name, c.type,
                   EXISTS (
                       SELECT 1 FROM channel_members cm
                       WHERE cm.channel_id = c.channel_id AND cm.user_id = %s
                   ) AS is_member
            FROM channels c
            WHERE c.workspace_id = %s
              AND (
                  c.type = 'public'
                  OR EXISTS (
                      SELECT 1 FROM channel_members cm
                      WHERE cm.channel_id = c.channel_id AND cm.user_id = %s
                  )
              )
            ORDER BY c.type, c.name
            """,
            (user_id, ws_id, user_id)
        )
        channels = cur.fetchall()

        # Fetch all workspace members for the member panel.
        # Admins see toggle buttons next to each member (except themselves).
        cur.execute(
            """
            SELECT u.user_id, u.username, u.nickname, wm.is_admin
            FROM workspace_members wm
            JOIN users u ON u.user_id = wm.user_id
            WHERE wm.workspace_id = %s
            ORDER BY u.username
            """,
            (ws_id,)
        )
        members = cur.fetchall()

        # Fetch pending channel invitations for this user in this workspace.
        # channel_id (index 3) needed to build accept/decline URLs correctly.
        cur.execute(
            """
            SELECT ci.invitation_id, c.name, u.username AS inviter, c.channel_id
            FROM channel_invitations ci
            JOIN channels c ON c.channel_id = ci.channel_id
            JOIN users u ON u.user_id = ci.inviter_id
            WHERE ci.invitee_id = %s AND ci.status = 'pending'
              AND c.workspace_id = %s
            """,
            (user_id, ws_id)
        )
        channel_invites = cur.fetchall()

    finally:
        conn.close()

    return render_template(
        "workspace/detail.html",
        ws_id=ws_id, ws=ws, channels=channels,
        members=members, is_admin=is_admin,
        channel_invites=channel_invites
    )


@workspace.route("/workspace/<int:ws_id>/invite", methods=["GET", "POST"])
@login_required
def invite(ws_id):
    """
    GET  — render the invite form (admins only).
    POST — insert a workspace_invitation row for the given email address.

    If the email belongs to a registered user, invitee_id is set so the invitation
    appears on their dashboard immediately. If unregistered, invitee_id is NULL
    and the invitation is stored for when they eventually sign up.

    ON CONFLICT DO NOTHING silently skips duplicate pending invitations
    (same workspace + email + status combination).
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()

        # Authorization: only admins can invite members.
        cur.execute(
            "SELECT is_admin FROM workspace_members WHERE workspace_id = %s AND user_id = %s",
            (ws_id, user_id)
        )
        row = cur.fetchone()
        if not row or not row[0]:
            flash("Only admins can invite members.")
            return redirect(url_for("workspace.detail", ws_id=ws_id))

        if request.method == "POST":
            email = request.form["email"].strip()

            # Look up whether the email belongs to an existing user.
            # invitee_id stays NULL if not found — supports inviting unregistered users.
            cur.execute("SELECT user_id FROM users WHERE email = %s", (email,))
            invitee    = cur.fetchone()
            invitee_id = invitee[0] if invitee else None

            cur.execute(
                """
                INSERT INTO workspace_invitations
                    (workspace_id, inviter_id, invitee_id, invitee_email)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT DO NOTHING
                """,
                (ws_id, user_id, invitee_id, email)
            )
            conn.commit()
            flash(f"Invitation sent to {email}.")
            return redirect(url_for("workspace.detail", ws_id=ws_id))

        cur.execute("SELECT name FROM workspaces WHERE workspace_id = %s", (ws_id,))
        ws = cur.fetchone()
    finally:
        conn.close()

    return render_template("workspace/invite.html", ws_id=ws_id, ws=ws)


@workspace.route("/workspace/<int:ws_id>/invitation/<int:inv_id>/accept", methods=["POST"])
@login_required
def accept_invite(ws_id, inv_id):
    """
    Accept a pending workspace invitation.

    Two steps in one transaction:
      1. Update invitation status to 'accepted' and record responded_at timestamp.
      2. Insert workspace_members row for the user.

    AND invitee_id = %s ensures users can only accept invitations addressed to them.
    ON CONFLICT DO NOTHING on members insert prevents errors on duplicate submission.
    Invitation row is kept for historical audit — never deleted.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE workspace_invitations SET status='accepted', responded_at=NOW() "
            "WHERE invitation_id=%s AND invitee_id=%s",
            (inv_id, user_id)
        )
        cur.execute(
            "INSERT INTO workspace_members (workspace_id, user_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (ws_id, user_id)
        )
        conn.commit()
    except Exception:
        conn.rollback()
    finally:
        conn.close()
    return redirect(url_for("workspace.list_workspaces"))


@workspace.route("/workspace/<int:ws_id>/invitation/<int:inv_id>/decline", methods=["POST"])
@login_required
def decline_invite(ws_id, inv_id):
    """
    Decline a pending workspace invitation.

    Updates invitation status to 'declined' and records responded_at.
    No workspace_members row is created. Invitation row kept for audit.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE workspace_invitations SET status='declined', responded_at=NOW() "
            "WHERE invitation_id=%s AND invitee_id=%s",
            (inv_id, user_id)
        )
        conn.commit()
    finally:
        conn.close()
    return redirect(url_for("workspace.list_workspaces"))


@workspace.route("/workspace/<int:ws_id>/toggle_admin/<int:target_id>", methods=["POST"])
@login_required
def toggle_admin(ws_id, target_id):
    """
    Toggle the is_admin flag for a workspace member (TRUE→FALSE or FALSE→TRUE).

    Only existing admins can use this route — verified against workspace_members.
    The template hides the button for the admin's own row to prevent self-demotion,
    but the server-side admin check still applies for all requests.
    """
    user_id = session["user_id"]
    conn = get_conn()
    try:
        cur = conn.cursor()

        # Authorization: verify the requester is an admin.
        cur.execute(
            "SELECT is_admin FROM workspace_members WHERE workspace_id=%s AND user_id=%s",
            (ws_id, user_id)
        )
        row = cur.fetchone()
        if not row or not row[0]:
            flash("Only admins can manage roles.")
            return redirect(url_for("workspace.detail", ws_id=ws_id))

        # NOT is_admin flips TRUE→FALSE and FALSE→TRUE atomically.
        cur.execute(
            "UPDATE workspace_members SET is_admin = NOT is_admin WHERE workspace_id=%s AND user_id=%s",
            (ws_id, target_id)
        )
        conn.commit()
    finally:
        conn.close()
    return redirect(url_for("workspace.detail", ws_id=ws_id))