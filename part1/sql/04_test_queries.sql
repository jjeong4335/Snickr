-- ---------------------------------------------------------------------
-- (1)
-- ---------------------------------------------------------------------
INSERT INTO users (email, username, nickname, password_hash)
VALUES ('grace@nyu.edu', 'grace', 'Grace H.', 'hash_grace')
RETURNING user_id, email, username, nickname, created_at;


-- ---------------------------------------------------------------------
-- (2a)
-- ---------------------------------------------------------------------
BEGIN;
WITH new_channel AS (
    INSERT INTO channels (workspace_id, name, type, created_by)
    SELECT  (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
            'random',
            'public',
            (SELECT user_id FROM users WHERE username='alice')
    WHERE EXISTS (
        SELECT 1
        FROM workspace_members
        WHERE workspace_id = (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')
          AND user_id      = (SELECT user_id FROM users WHERE username='alice')
    )
    RETURNING channel_id, workspace_id, name, type, created_by, created_at
)
INSERT INTO channel_members (channel_id, user_id)
SELECT channel_id, (SELECT user_id FROM users WHERE username='alice')
FROM   new_channel;
COMMIT;

-- Verify the new channel and its lone member:
SELECT c.channel_id, c.name, c.type, u.username AS member
FROM   channels c
JOIN   channel_members cm ON cm.channel_id = c.channel_id
JOIN   users u ON u.user_id = cm.user_id
WHERE  c.name = 'random'
  AND  c.workspace_id = (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty');


-- ---------------------------------------------------------------------
-- (2b)
-- ---------------------------------------------------------------------
BEGIN;
WITH new_channel AS (
    INSERT INTO channels (workspace_id, name, type, created_by)
    SELECT  (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
            'spam',
            'public',
            (SELECT user_id FROM users WHERE username='frank')
    WHERE EXISTS (
        SELECT 1
        FROM workspace_members
        WHERE workspace_id = (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')
          AND user_id      = (SELECT user_id FROM users WHERE username='frank')
    )
    RETURNING channel_id, workspace_id, name, type, created_by, created_at
)
INSERT INTO channel_members (channel_id, user_id)
SELECT channel_id, (SELECT user_id FROM users WHERE username='frank')
FROM   new_channel;
COMMIT;

SELECT count(*) AS spam_channels_created
FROM   channels
WHERE  name = 'spam';


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
LEFT JOIN channel_invitations ci ON ci.channel_id = c.channel_id
WHERE   c.workspace_id = (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')
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
WHERE   m.channel_id = (
            SELECT channel_id FROM channels
            WHERE  name = 'grad-admissions'
              AND  workspace_id = (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')
        )
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
WHERE   m.sender_id = (SELECT user_id FROM users WHERE username='alice')
ORDER BY m.posted_at ASC, m.message_id ASC;


-- ---------------------------------------------------------------------
-- (7a)
--
-- eve's "perpendicular" message in #budget is hidden because alice is NOT a member of that channel.
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
  AND   EXISTS (
            SELECT 1 FROM channel_members cm
            WHERE cm.channel_id = c.channel_id
              AND cm.user_id    = (SELECT user_id FROM users WHERE username='alice')
        )
  AND   EXISTS (
            SELECT 1 FROM workspace_members wm
            WHERE wm.workspace_id = w.workspace_id
              AND wm.user_id      = (SELECT user_id FROM users WHERE username='alice')
        )
ORDER BY m.posted_at ASC, m.message_id ASC;


-- ---------------------------------------------------------------------
-- (7b)
--
-- Same query for eve  ->  she should additionally see her
-- own #budget message and the Coop-Board #general one (carol's NYU
-- messages must be hidden because eve is not in NYU Faculty).
-- ---------------------------------------------------------------------
SELECT  m.message_id,
        w.name        AS workspace_name,
        c.name        AS channel_name,
        sender.username AS sender_username,
        m.body
FROM    messages   m
JOIN    channels   c       ON c.channel_id   = m.channel_id
JOIN    workspaces w       ON w.workspace_id = c.workspace_id
JOIN    users      sender  ON sender.user_id = m.sender_id
WHERE   m.body ILIKE '%perpendicular%'
  AND   EXISTS (SELECT 1 FROM channel_members cm
                WHERE cm.channel_id = c.channel_id
                  AND cm.user_id    = (SELECT user_id FROM users WHERE username='eve'))
  AND   EXISTS (SELECT 1 FROM workspace_members wm
                WHERE wm.workspace_id = w.workspace_id
                  AND wm.user_id      = (SELECT user_id FROM users WHERE username='eve'))
ORDER BY m.posted_at ASC;
