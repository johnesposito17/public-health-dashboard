"""
Load raw CSV files into PostgreSQL under the 'raw' schema.

Tables created:
  raw.cdc_places_county  — CDC PLACES county chronic disease data
  raw.acs_county_2022    — ACS 5-Year demographic data (loads if file exists)

Each run does a full replace (drop + recreate), so the script is safe
to re-run after pulling updated source data.

Connection is read from environment variables (set in .env):
  PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD
"""

import os
import sys
import pandas as pd
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

PLACES_FILE = RAW_DIR / "cdc_places_county.csv"
ACS_FILE    = RAW_DIR / "acs_county_2022.csv"

RAW_SCHEMA  = "raw"


def get_engine():
    host     = os.getenv("PG_HOST", "localhost")
    port     = os.getenv("PG_PORT", "5432")
    db       = os.getenv("PG_DB", "health_dashboard")
    user     = os.getenv("PG_USER", "postgres")
    password = os.getenv("PG_PASSWORD", "postgres")
    url      = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}"
    return create_engine(url, future=True)


def ensure_schema(engine, schema: str) -> None:
    with engine.begin() as conn:
        conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))
    print(f"  Schema '{schema}' ready.")


def load_csv(engine, csv_path: Path, table: str, schema: str, dtype_overrides: dict = None) -> int:
    print(f"\nLoading {csv_path.name} → {schema}.{table} ...")
    df = pd.read_csv(csv_path, dtype=dtype_overrides or {}, low_memory=False)
    print(f"  Read {len(df):,} rows x {len(df.columns)} cols")

    df.to_sql(
        name=table,
        con=engine,
        schema=schema,
        if_exists="replace",   # full refresh on each run
        index=False,
        chunksize=5_000,
        method="multi",
    )
    # Verify row count in Postgres matches what we loaded
    with engine.connect() as conn:
        pg_count = conn.execute(
            text(f'SELECT COUNT(*) FROM "{schema}"."{table}"')
        ).scalar()

    print(f"  Postgres row count: {pg_count:,}  {'OK' if pg_count == len(df) else 'MISMATCH'}")
    return pg_count


def main() -> None:
    engine = get_engine()

    # Quick connectivity check
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("Connected to Postgres successfully.")
    except Exception as exc:
        print(f"ERROR: Could not connect to Postgres.\n{exc}", file=sys.stderr)
        print(
            "\nMake sure the Docker container is running:\n"
            "  docker run --name ph-dashboard \\\n"
            "    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \\\n"
            "    -e POSTGRES_DB=health_dashboard \\\n"
            "    -p 5432:5432 -d postgres:16",
            file=sys.stderr,
        )
        sys.exit(1)

    ensure_schema(engine, RAW_SCHEMA)

    # PLACES — always expected
    if not PLACES_FILE.exists():
        print(f"ERROR: {PLACES_FILE} not found. Run scripts/pull_cdc_places.py first.", file=sys.stderr)
        sys.exit(1)

    load_csv(
        engine, PLACES_FILE,
        table="cdc_places_county",
        schema=RAW_SCHEMA,
        # Keep FIPS as text to preserve leading zeros
        dtype_overrides={"locationid": str},
    )

    # ACS — optional until Census API key is activated
    if ACS_FILE.exists():
        load_csv(
            engine, ACS_FILE,
            table="acs_county_2022",
            schema=RAW_SCHEMA,
            dtype_overrides={"fips": str, "state": str, "county": str},
        )
    else:
        print(
            f"\nNote: {ACS_FILE.name} not found — skipping ACS load.\n"
            "Run scripts/pull_acs_data.py once your Census API key is activated."
        )

    print("\nDone. Raw schema tables:")
    with engine.connect() as conn:
        rows = conn.execute(
            text("""
                SELECT table_name, pg_size_pretty(pg_total_relation_size(
                    quote_ident(table_schema)||'.'||quote_ident(table_name)
                )) AS size
                FROM information_schema.tables
                WHERE table_schema = :schema
                ORDER BY table_name
            """),
            {"schema": RAW_SCHEMA},
        ).fetchall()
    for table_name, size in rows:
        print(f"  raw.{table_name:<30} {size}")


if __name__ == "__main__":
    main()
