-- ---------------------------------------------------------------------
-- (1)
-- ---------------------------------------------------------------------
INSERT INTO users (email, username, nickname, password_hash)
VALUES (:'email', :'username', :'nickname', :'password_hash')
RETURNING user_id, email, username, nickname, created_at;


-- ---------------------------------------------------------------------
-- (2)
-- ---------------------------------------------------------------------
BEGIN;

-- 2a) Insert the channel only if :user_id is a workspace member.
WITH new_channel AS (
    INSERT INTO channels (workspace_id, name, type, created_by)
    SELECT :workspace_id, :'channel_name', 'public', :user_id
    WHERE EXISTS (
        SELECT 1
        FROM workspace_members
        WHERE workspace_id = :workspace_id
          AND user_id      = :user_id
    )
    RETURNING channel_id, workspace_id, name, type, created_by, created_at
)
-- 2b) Auto-join the creator to the channel they just created.
INSERT INTO channel_members (channel_id, user_id)
SELECT channel_id, :user_id FROM new_channel;

COMMIT;


-- ---------------------------------------------------------------------
-- (3)
-- ---------------------------------------------------------------------
SELECT  w.workspace_id,
        w.name              AS workspace_name,
        u.user_id           AS admin_user_id,
        u.username          AS admin_username,
        u.nickname          AS admin_nickname
FROM    workspaces        AS w
JOIN    workspace_members AS wm ON wm.workspace_id = w.workspace_id
JOIN    users             AS u  ON u.user_id       = wm.user_id
WHERE   wm.is_admin = TRUE
ORDER BY w.workspace_id, u.username;


-- ---------------------------------------------------------------------
-- (4)
-- ---------------------------------------------------------------------
SELECT
        c.channel_id,
        c.name AS channel_name,
        COUNT(*) FILTER (
            WHERE ci.invitation_id IS NOT NULL
              AND ci.invited_at < NOW() - INTERVAL '5 days'
              AND NOT EXISTS (
                    SELECT 1 FROM channel_members cm
                    WHERE cm.channel_id = c.channel_id
                      AND cm.user_id    = ci.invitee_id
              )
        ) AS pending_invites_older_than_5_days
FROM    channels c
LEFT JOIN channel_invitations ci
       ON ci.channel_id = c.channel_id
WHERE   c.workspace_id = :workspace_id
  AND   c.type         = 'public'
GROUP BY c.channel_id, c.name
ORDER BY c.name;


-- ---------------------------------------------------------------------
-- (5)
-- ---------------------------------------------------------------------
SELECT  m.message_id,
        m.posted_at,
        u.username AS sender_username,
        u.nickname AS sender_nickname,
        m.body
FROM    messages m
JOIN    users    u ON u.user_id = m.sender_id
WHERE   m.channel_id = :channel_id
ORDER BY m.posted_at ASC, m.message_id ASC;


-- ---------------------------------------------------------------------
-- (6)
-- ---------------------------------------------------------------------
SELECT  m.message_id,
        m.posted_at,
        w.name      AS workspace_name,
        c.name      AS channel_name,
        c.type      AS channel_type,
        m.body
FROM    messages   m
JOIN    channels   c ON c.channel_id   = m.channel_id
JOIN    workspaces w ON w.workspace_id = c.workspace_id
WHERE   m.sender_id = :user_id
ORDER BY m.posted_at ASC, m.message_id ASC;


-- ---------------------------------------------------------------------
-- (7)
-- ---------------------------------------------------------------------
SELECT  m.message_id,
        m.posted_at,
        w.name        AS workspace_name,
        c.name        AS channel_name,
        c.type        AS channel_type,
        sender.username AS sender_username,
        m.body
FROM    messages   m
JOIN    channels   c       ON c.channel_id   = m.channel_id
JOIN    workspaces w       ON w.workspace_id = c.workspace_id
JOIN    users      sender  ON sender.user_id = m.sender_id
WHERE   m.body ILIKE '%perpendicular%'
  AND   EXISTS (                              -- channel membership
            SELECT 1 FROM channel_members cm
            WHERE cm.channel_id = c.channel_id
              AND cm.user_id    = :user_id
        )
  AND   EXISTS (                              -- workspace membership
            SELECT 1 FROM workspace_members wm
            WHERE wm.workspace_id = w.workspace_id
              AND wm.user_id      = :user_id
        )
ORDER BY m.posted_at ASC, m.message_id ASC;
