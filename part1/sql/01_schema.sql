DROP TABLE IF EXISTS messages              CASCADE;
DROP TABLE IF EXISTS channel_invitations   CASCADE;
DROP TABLE IF EXISTS channel_members       CASCADE;
DROP TABLE IF EXISTS channels              CASCADE;
DROP TABLE IF EXISTS workspace_invitations CASCADE;
DROP TABLE IF EXISTS workspace_members     CASCADE;
DROP TABLE IF EXISTS workspaces            CASCADE;
DROP TABLE IF EXISTS users                 CASCADE;

-- ---------------------------------------------------------------------
-- 1. users
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id        SERIAL       PRIMARY KEY,
    email          VARCHAR(254) NOT NULL UNIQUE,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    nickname       VARCHAR(50)  NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_email_format_chk CHECK (email LIKE '%_@_%.__%')
);

-- ---------------------------------------------------------------------
-- 2. workspaces
-- ---------------------------------------------------------------------
CREATE TABLE workspaces (
    workspace_id   SERIAL        PRIMARY KEY,
    name           VARCHAR(100)  NOT NULL UNIQUE,
    description    VARCHAR(500),
    created_by     INTEGER       NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT workspaces_creator_fk
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 3. workspace_members
-- ---------------------------------------------------------------------
CREATE TABLE workspace_members (
    workspace_id   INTEGER      NOT NULL,
    user_id        INTEGER      NOT NULL,
    is_admin       BOOLEAN      NOT NULL DEFAULT FALSE,
    joined_at      TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (workspace_id, user_id),
    CONSTRAINT wm_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(workspace_id)
        ON DELETE CASCADE,
    CONSTRAINT wm_user_fk
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE
);

CREATE INDEX wm_user_idx ON workspace_members(user_id);

-- ---------------------------------------------------------------------
-- 4. workspace_invitations
-- ---------------------------------------------------------------------
CREATE TABLE workspace_invitations (
    invitation_id   SERIAL        PRIMARY KEY,
    workspace_id    INTEGER       NOT NULL,
    inviter_id      INTEGER       NOT NULL,
    invitee_id      INTEGER,                       -- NULL until/unless registered
    invitee_email   VARCHAR(254)  NOT NULL,
    status          VARCHAR(10)   NOT NULL DEFAULT 'pending',
    invited_at      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at    TIMESTAMPTZ,
    CONSTRAINT wi_status_chk
        CHECK (status IN ('pending','accepted','declined')),
    CONSTRAINT wi_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(workspace_id)
        ON DELETE CASCADE,
    CONSTRAINT wi_inviter_fk
        FOREIGN KEY (inviter_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT wi_invitee_fk
        FOREIGN KEY (invitee_id) REFERENCES users(user_id)
        ON DELETE SET NULL,
    -- Avoid duplicate pending invitations for the same workspace/email.
    CONSTRAINT wi_unique_pending UNIQUE (workspace_id, invitee_email, status)
);

-- ---------------------------------------------------------------------
-- 5. channels
-- ---------------------------------------------------------------------
CREATE TABLE channels (
    channel_id     SERIAL        PRIMARY KEY,
    workspace_id   INTEGER       NOT NULL,
    name           VARCHAR(80)   NOT NULL,
    type           VARCHAR(10)   NOT NULL,
    created_by     INTEGER       NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ch_type_chk CHECK (type IN ('public','private','direct')),
    CONSTRAINT ch_unique_name_in_ws UNIQUE (workspace_id, name),
    CONSTRAINT ch_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(workspace_id)
        ON DELETE CASCADE,
    CONSTRAINT ch_creator_fk
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE INDEX channels_workspace_idx ON channels(workspace_id);

-- ---------------------------------------------------------------------
-- 6. channel_members
-- ---------------------------------------------------------------------
CREATE TABLE channel_members (
    channel_id   INTEGER      NOT NULL,
    user_id      INTEGER      NOT NULL,
    joined_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (channel_id, user_id),
    CONSTRAINT cm_channel_fk
        FOREIGN KEY (channel_id) REFERENCES channels(channel_id)
        ON DELETE CASCADE,
    CONSTRAINT cm_user_fk
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE
);

CREATE INDEX cm_user_idx ON channel_members(user_id);

-- ---------------------------------------------------------------------
-- 7. channel_invitations
-- ---------------------------------------------------------------------
CREATE TABLE channel_invitations (
    invitation_id   SERIAL        PRIMARY KEY,
    channel_id      INTEGER       NOT NULL,
    inviter_id      INTEGER       NOT NULL,
    invitee_id      INTEGER       NOT NULL,
    status          VARCHAR(10)   NOT NULL DEFAULT 'pending',
    invited_at      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at    TIMESTAMPTZ,
    CONSTRAINT ci_status_chk
        CHECK (status IN ('pending','accepted','declined')),
    CONSTRAINT ci_channel_fk
        FOREIGN KEY (channel_id) REFERENCES channels(channel_id)
        ON DELETE CASCADE,
    CONSTRAINT ci_inviter_fk
        FOREIGN KEY (inviter_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ci_invitee_fk
        FOREIGN KEY (invitee_id) REFERENCES users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT ci_unique_pending UNIQUE (channel_id, invitee_id, status)
);

-- ---------------------------------------------------------------------
-- 8. messages
-- ---------------------------------------------------------------------
CREATE TABLE messages (
    message_id   BIGSERIAL    PRIMARY KEY,
    channel_id   INTEGER      NOT NULL,
    sender_id    INTEGER      NOT NULL,
    body         TEXT         NOT NULL,
    posted_at    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT msg_channel_fk
        FOREIGN KEY (channel_id) REFERENCES channels(channel_id)
        ON DELETE CASCADE,
    CONSTRAINT msg_sender_fk
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT msg_body_nonempty_chk CHECK (length(btrim(body)) > 0)
);

CREATE INDEX messages_channel_time_idx ON messages(channel_id, posted_at);
CREATE INDEX messages_sender_idx       ON messages(sender_id);
