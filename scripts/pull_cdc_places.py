"""
Pull CDC PLACES county-level chronic disease data via the Socrata Open Data API.

Dataset : PLACES Local Data for Better Health, County Data 2025 release (year=2023)
Source  : https://data.cdc.gov/resource/swc5-untb
Output  : data/raw/cdc_places_county.csv

We pull crude-prevalence rows only. Age-adjusted rows are useful for cross-county
comparisons but create duplicate rows that complicate downstream joins; that design
decision is documented in docs/NOTES.md.
"""

import os
import sys
import time
import requests
import pandas as pd
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_URL   = "https://data.cdc.gov/resource/swc5-untb.json"
PAGE_SIZE  = 10_000
RAW_DIR    = Path(__file__).resolve().parent.parent / "data" / "raw"

# Pull crude prevalence only (CrdPrv). Switch to AgeAdjPrv for age-standardized analysis.
FILTER_TYPE_ID = "CrdPrv"


def fetch_page(offset: int, session: requests.Session) -> list[dict]:
    params = {
        "$limit":  PAGE_SIZE,
        "$offset": offset,
        "$where":  f"datavaluetypeid='{FILTER_TYPE_ID}'",
        "$order":  "locationid,measureid",
    }
    resp = session.get(BASE_URL, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.headers.update({"Accept": "application/json"})

    # Socrata app token removes per-IP rate limits. Register free at:
    # https://data.cdc.gov/login  → Developer Settings → Create New App Token
    app_token = os.getenv("SOCRATA_APP_TOKEN")
    if app_token:
        session.headers["X-App-Token"] = app_token
    else:
        print("Note: SOCRATA_APP_TOKEN not set — unauthenticated rate limits apply.")

    records: list[dict] = []
    offset = 0
    print("Pulling CDC PLACES county data (crude prevalence only)...")

    while True:
        page = fetch_page(offset, session)
        if not page:
            break
        records.extend(page)
        print(f"  {len(records):>8,} rows fetched  (offset={offset:,})")
        if len(page) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
        time.sleep(0.3)  # polite pacing between pages

    if not records:
        print("ERROR: no records returned. Check network or the resource ID.", file=sys.stderr)
        sys.exit(1)

    df = pd.DataFrame(records)

    # Drop Socrata computed geometry columns — not needed downstream
    df = df.drop(
        columns=[c for c in df.columns if c.startswith(":@")],
        errors="ignore",
    )

    # Coerce numeric columns
    for col in ("data_value", "low_confidence_limit", "high_confidence_limit",
                "totalpopulation", "totalpop18plus"):
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # Ensure FIPS is zero-padded to 5 characters (locationid should already be, but verify)
    df["locationid"] = df["locationid"].astype(str).str.zfill(5)

    print(f"\nSummary")
    print(f"  Total rows      : {len(df):,}")
    print(f"  Unique counties : {df['locationid'].nunique():,}")
    print(f"  Unique measures : {df['measureid'].nunique()}")
    print(f"  Measure IDs     : {sorted(df['measureid'].unique())}")
    print(f"  Year(s)         : {sorted(df['year'].unique())}")
    print(f"  Null data_value : {df['data_value'].isna().sum():,}")

    out_path = RAW_DIR / "cdc_places_county.csv"
    df.to_csv(out_path, index=False)
    print(f"\nSaved → {out_path}  ({len(df):,} rows x {len(df.columns)} cols)")


if __name__ == "__main__":
    main()
