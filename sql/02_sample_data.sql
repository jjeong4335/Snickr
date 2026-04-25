-- =====================================================================
-- Snickr  -  Sample data for testing
-- 
--      USERS                                WORKSPACES
--      -----                                ----------
--      alice  (admin of W1, member of W2)   W1: NYU Faculty
--      bob    (admin of W1)                 W2: Coop Board
--      carol  (member of W1)
--      david  (member of W1)
--      eve    (admin of W2)
--      frank  (no workspaces)
--
--      W1 channels:
--          #general            public  - alice, bob, carol, david
--          #grad-admissions    public  - alice, bob, carol
--          #undergrad-edu      public  - alice, bob
--          #hiring             private - alice, bob
--          dm:alice-carol      direct  - alice, carol
--
--      W2 channels:
--          #general            public  - eve, alice
--          #budget             public  - eve
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
INSERT INTO users (email, username, nickname, password_hash, created_at) VALUES
    ('alice@nyu.edu',    'alice',  'Alice K.',  'hash_alice', NOW() - INTERVAL '60 days'),
    ('bob@nyu.edu',      'bob',    'Bobby',     'hash_bob',   NOW() - INTERVAL '55 days'),
    ('carol@nyu.edu',    'carol',  'Caro',      'hash_carol', NOW() - INTERVAL '50 days'),
    ('david@nyu.edu',    'david',  'Dave',      'hash_david', NOW() - INTERVAL '40 days'),
    ('eve@example.com',  'eve',    'Evie',      'hash_eve',   NOW() - INTERVAL '30 days'),
    ('frank@coop.com',   'frank',  'Frankie',   'hash_frank', NOW() - INTERVAL '20 days');

-- ---------------------------------------------------------------------
-- Workspaces
-- ---------------------------------------------------------------------
INSERT INTO workspaces (name, description, created_by, created_at) VALUES
    ('NYU Faculty', 'Faculty discussion workspace for the CS department.',
        (SELECT user_id FROM users WHERE username='alice'),
        NOW() - INTERVAL '45 days'),
    ('Coop Board',  'Workspace for the building''s coop board members.',
        (SELECT user_id FROM users WHERE username='eve'),
        NOW() - INTERVAL '25 days');

-- ---------------------------------------------------------------------
-- Workspace memberships
-- ---------------------------------------------------------------------
-- W1: NYU Faculty
INSERT INTO workspace_members (workspace_id, user_id, is_admin, joined_at) VALUES
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='alice'),  TRUE,  NOW() - INTERVAL '45 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='bob'),    TRUE,  NOW() - INTERVAL '44 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='carol'),  FALSE, NOW() - INTERVAL '42 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='david'),  FALSE, NOW() - INTERVAL '40 days');

-- W2: Coop Board
INSERT INTO workspace_members (workspace_id, user_id, is_admin, joined_at) VALUES
    ((SELECT workspace_id FROM workspaces WHERE name='Coop Board'),
     (SELECT user_id FROM users WHERE username='eve'),    TRUE,  NOW() - INTERVAL '25 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='Coop Board'),
     (SELECT user_id FROM users WHERE username='alice'),  FALSE, NOW() - INTERVAL '20 days');

-- ---------------------------------------------------------------------
-- Workspace invitations
-- ---------------------------------------------------------------------
-- alice invited eve to NYU Faculty 6 days ago (still pending)
INSERT INTO workspace_invitations
    (workspace_id, inviter_id, invitee_id, invitee_email, status, invited_at)
VALUES
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='alice'),
     (SELECT user_id FROM users WHERE username='eve'),
     'eve@example.com', 'pending', NOW() - INTERVAL '6 days'),
-- bob invited frank to NYU Faculty 10 days ago (still pending)
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     (SELECT user_id FROM users WHERE username='bob'),
     (SELECT user_id FROM users WHERE username='frank'),
     'frank@coop.com', 'pending', NOW() - INTERVAL '10 days'),
-- eve invited alice to Coop Board 22 days ago (accepted - shows historical record)
    ((SELECT workspace_id FROM workspaces WHERE name='Coop Board'),
     (SELECT user_id FROM users WHERE username='eve'),
     (SELECT user_id FROM users WHERE username='alice'),
     'alice@nyu.edu', 'accepted', NOW() - INTERVAL '22 days');

-- ---------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------
-- W1 channels
INSERT INTO channels (workspace_id, name, type, created_by, created_at) VALUES
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     'general',         'public',
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '45 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     'grad-admissions', 'public',
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '30 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     'undergrad-edu',   'public',
     (SELECT user_id FROM users WHERE username='bob'),   NOW() - INTERVAL '20 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     'hiring',          'private',
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '15 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='NYU Faculty'),
     'dm:alice-carol',  'direct',
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '10 days');

-- W2 channels
INSERT INTO channels (workspace_id, name, type, created_by, created_at) VALUES
    ((SELECT workspace_id FROM workspaces WHERE name='Coop Board'),
     'general', 'public',
     (SELECT user_id FROM users WHERE username='eve'), NOW() - INTERVAL '25 days'),
    ((SELECT workspace_id FROM workspaces WHERE name='Coop Board'),
     'budget',  'public',
     (SELECT user_id FROM users WHERE username='eve'), NOW() - INTERVAL '15 days');

-- ---------------------------------------------------------------------
-- Channel memberships
-- ---------------------------------------------------------------------
-- W1 #general : alice, bob, carol, david
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '45 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),   NOW() - INTERVAL '44 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'), NOW() - INTERVAL '42 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='david'), NOW() - INTERVAL '40 days');

-- W1 #grad-admissions : alice, bob, carol
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '30 days'),
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),   NOW() - INTERVAL '29 days'),
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'), NOW() - INTERVAL '8 days');

-- W1 #undergrad-edu : alice, bob
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '20 days'),
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),   NOW() - INTERVAL '19 days');

-- W1 #hiring (private) : alice, bob
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='hiring' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '15 days'),
    ((SELECT channel_id FROM channels WHERE name='hiring' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),   NOW() - INTERVAL '14 days');

-- W1 dm:alice-carol (direct) : alice, carol
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='dm:alice-carol' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '10 days'),
    ((SELECT channel_id FROM channels WHERE name='dm:alice-carol' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'), NOW() - INTERVAL '10 days');

-- W2 #general : eve, alice
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='eve'),   NOW() - INTERVAL '25 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='alice'), NOW() - INTERVAL '20 days');

-- W2 #budget : eve only (alice is not a member)
INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES
    ((SELECT channel_id FROM channels WHERE name='budget' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='eve'),   NOW() - INTERVAL '15 days');

-- ---------------------------------------------------------------------
-- Channel invitations
--
-- The combinations below are designed so that query #4 returns:
--      #general          --> 0
--      #grad-admissions  --> 1   (david, invited 7 days ago, not joined)
--      #undergrad-edu    --> 1   (david, invited 6 days ago, not joined)
-- and the carol/undergrad-edu invitation (3 days ago) is NOT counted because 3 < 5.
-- ---------------------------------------------------------------------
-- alice invited carol to #grad-admissions 9 days ago - accepted

INSERT INTO channel_invitations
    (channel_id, inviter_id, invitee_id, status, invited_at, responded_at)
VALUES
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     (SELECT user_id FROM users WHERE username='carol'),
     'accepted', NOW() - INTERVAL '9 days', NOW() - INTERVAL '8 days'),
-- bob invited david to #grad-admissions 7 days ago - still pending
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),
     (SELECT user_id FROM users WHERE username='david'),
     'pending',  NOW() - INTERVAL '7 days', NULL),
-- alice invited david to #undergrad-edu 6 days ago - still pending
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     (SELECT user_id FROM users WHERE username='david'),
     'pending',  NOW() - INTERVAL '6 days', NULL),
-- bob invited carol to #undergrad-edu 3 days ago (less than 5 - excluded)
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),
     (SELECT user_id FROM users WHERE username='carol'),
     'pending',  NOW() - INTERVAL '3 days', NULL),
-- alice invited bob to #hiring (private) 13 days ago - accepted
    ((SELECT channel_id FROM channels WHERE name='hiring' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     (SELECT user_id FROM users WHERE username='bob'),
     'accepted', NOW() - INTERVAL '13 days', NOW() - INTERVAL '12 days');

-- ---------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------
INSERT INTO messages (channel_id, sender_id, body, posted_at) VALUES
    -- W1 #general
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     'Welcome everyone to the new semester!',
     NOW() - INTERVAL '40 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),
     'Reminder: faculty meeting on Friday at 3pm.',
     NOW() - INTERVAL '38 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'),
     'I noticed the new building''s wall is perpendicular to the old one.',
     NOW() - INTERVAL '12 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='david'),
     'Anyone want to grab coffee after the meeting?',
     NOW() - INTERVAL '11 days'),

    -- W1 #grad-admissions
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     'PhD application deadline is December 15.',
     NOW() - INTERVAL '20 days'),
    ((SELECT channel_id FROM channels WHERE name='grad-admissions' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'),
     'I think we should add a perpendicular evaluation criterion this year.',
     NOW() - INTERVAL '5 days'),

    -- W1 #undergrad-edu
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     'Discussing the new curriculum next Monday.',
     NOW() - INTERVAL '15 days'),
    ((SELECT channel_id FROM channels WHERE name='undergrad-edu' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),
     'We need at least four new TAs for CS-UY 1114.',
     NOW() - INTERVAL '14 days'),

    -- W1 #hiring  (private)
    ((SELECT channel_id FROM channels WHERE name='hiring' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     'Let''s discuss the candidate from MIT.',
     NOW() - INTERVAL '8 days'),
    ((SELECT channel_id FROM channels WHERE name='hiring' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='bob'),
     'Their research is perpendicular to ours - good fit.',
     NOW() - INTERVAL '7 days'),

    -- W1 dm:alice-carol  (direct)
    ((SELECT channel_id FROM channels WHERE name='dm:alice-carol' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='alice'),
     'Hey Carol, do you want to co-teach the new seminar?',
     NOW() - INTERVAL '9 days'),
    ((SELECT channel_id FROM channels WHERE name='dm:alice-carol' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='NYU Faculty')),
     (SELECT user_id FROM users WHERE username='carol'),
     'Sure, sounds great!',
     NOW() - INTERVAL '9 days'),

    -- W2 #general
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='eve'),
     'Annual coop meeting will be held next Tuesday.',
     NOW() - INTERVAL '6 days'),
    ((SELECT channel_id FROM channels WHERE name='general' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='alice'),
     'I will bring snacks. The new chairs are perpendicular to the wall.',
     NOW() - INTERVAL '4 days'),

    -- W2 #budget   (alice is NOT a member, so query #7 must HIDE this)
    ((SELECT channel_id FROM channels WHERE name='budget' AND workspace_id =
        (SELECT workspace_id FROM workspaces WHERE name='Coop Board')),
     (SELECT user_id FROM users WHERE username='eve'),
     'This year''s expenses are perpendicular to last year''s pattern.',
     NOW() - INTERVAL '3 days');

COMMIT;
