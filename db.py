"""
db.py — Database Connection Factory

Provides a single function get_conn() that returns a new psycopg2 connection
using credentials loaded from environment variables (.env file).

Why a factory function instead of a global connection?
  - Flask handles requests concurrently; a single shared connection would cause
    race conditions between requests.
  - Each request calls get_conn(), uses the connection, and closes it in a
    finally block — clean and safe.

Environment variables (set in .env):
  DB_HOST     : PostgreSQL host (default: localhost)
  DB_NAME     : database name (default: snickr)
  DB_USER     : database user
  DB_PASSWORD : database password
"""

import psycopg2
import os
from dotenv import load_dotenv

# Load .env file into environment variables.
# This must run before os.getenv() calls below.
load_dotenv()


def get_conn():
    """
    Return a new psycopg2 connection to the snickr PostgreSQL database.

    psycopg2 connections default to autocommit=False, meaning every
    operation runs inside a transaction. Callers must explicitly call
    conn.commit() on success or conn.rollback() on failure.

    Usage pattern in every route:
        conn = get_conn()
        try:
            cur = conn.cursor()
            cur.execute("...", (params,))
            conn.commit()
        except Exception:
            conn.rollback()
        finally:
            conn.close()  # always close, even on error
    """
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        dbname=os.getenv("DB_NAME", "snickr"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "")
    )