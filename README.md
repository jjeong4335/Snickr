# Snickr — Slack-like Collaboration Platform

CS-GY 6083 · Spring 2026 · NYU Tandon School of Engineering

## Project Structure

```
Snickr/
├── sql/
│   ├── 01_schema.sql       # DDL: 8 tables, indexes, constraints
│   ├── 02_sample_data.sql  # Hand-crafted test data
│   ├── 03_queries.sql      # 7 required queries (with placeholders)
│   └── 04_test_queries.sql # Same queries with concrete values
├── report/                 # ER diagram and report source
├── screenshots/            # pgAdmin query result screenshots
├── web/                    # Part 2: Flask web application
│   ├── app.py              # Entry point, blueprint registration
│   ├── auth.py             # Register, login, logout, profile
│   ├── workspace.py        # Workspace CRUD, invitations, admin
│   ├── channel.py          # Channel create, join, invite
│   ├── message.py          # Message posting and keyword search
│   ├── db.py               # Database connection factory
│   ├── utils.py            # login_required decorator
│   ├── static/             # CSS stylesheet
│   └── templates/          # Jinja2 HTML templates
└── README.md
```

## Setup (Part 2)

### 1. Create the database

```bash
createdb -U  snickr
psql -U  -d snickr -f sql/01_schema.sql
psql -U  -d snickr -f sql/02_sample_data.sql
```

### 2. Configure environment

```bash
cd web
cp .env.example .env
# Edit .env: fill in DB_USER, DB_PASSWORD, SECRET_KEY
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Run

```bash
python app.py
```

Open http://127.0.0.1:5000 in your browser.

## Sample users

| Username | Password |
|----------|----------|
| alice    | alice    |
| bob      | bob      |
| carol    | carol    |
| eve      | eve      |

## Security

- **SQL Injection**: psycopg2 parameterized queries (`%s`)
- **XSS**: Jinja2 auto-escaping on all templates
- **Session**: Flask signed cookie with `SECRET_KEY`
- **Transactions**: explicit `commit()` / `rollback()` on every route