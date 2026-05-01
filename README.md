# Snickr — Slack-like Collaboration Platform

CS-GY 6083 · Spring 2026 · NYU Tandon School of Engineering

## Project Structure

Snickr/
├── sql/                   # Part 1: Database schema and queries
│   ├── 01_schema.sql      # DDL: 8 tables, indexes, constraints
│   ├── 02_sample_data.sql # Hand-crafted test data
│   ├── 03_queries.sql     # 7 required queries (with placeholders)
│   └── 04_test_queries.sql# Same queries with concrete values
├── report/                # Part 1: ER diagram and report source
├── screenshots/           # Part 1: pgAdmin query result screenshots
├── web/                   # Part 2: Flask web application
│   ├── app.py             # Entry point, blueprint registration
│   ├── auth.py            # Register, login, logout, profile
│   ├── workspace.py       # Workspace CRUD, invitations, admin management
│   ├── channel.py         # Channel create, join, invite (all types)
│   ├── message.py         # Message posting and keyword search
│   ├── db.py              # Database connection factory
│   ├── utils.py           # login_required decorator
│   ├── static/            # CSS stylesheet
│   └── templates/         # Jinja2 HTML templates
└── README.md

## Setup (Part 2)

### 1. Create the database

createdb -U <your_user> snickr
psql -U <your_user> -d snickr -f sql/01_schema.sql
psql -U <your_user> -d snickr -f sql/02_sample_data.sql

### 2. Configure environment

cd web
cp .env.example .env

### 3. Install dependencies

pip install -r requirements.txt

### 4. Run

python app.py

Open http://127.0.0.1:5000 in your browser.

## Sample users

| Username | Password |
|----------|----------|
| alice    | alice    |
| bob      | bob      |
| carol    | carol    |
| eve      | eve      |

## Security

- SQL Injection: psycopg2 parameterized queries
- XSS: Jinja2 auto-escaping on all templates
- Session: Flask signed cookie with SECRET_KEY
- Transactions: explicit commit() / rollback() on every route
