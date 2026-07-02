"""
Pull US Census ACS 5-Year Estimates (2022) at the county level.

Makes two API calls:
  1. Detailed tables (acs5)  — population, income, age, race/ethnicity, poverty
  2. Subject table S2701     — percent uninsured (civilian noninstitutionalized)

Joins both on the 5-digit FIPS code (state || county), computes percentage
fields from raw counts, then writes a single tidy CSV.

Output: data/raw/acs_county_2022.csv

CENSUS_API_KEY must be set in .env. Get a free key at:
https://api.census.gov/data/key_signup.html
"""

import os
import sys
import requests
import pandas as pd
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

CENSUS_API_KEY = os.getenv("CENSUS_API_KEY", "").strip()
if not CENSUS_API_KEY:
    print(
        "ERROR: CENSUS_API_KEY is not set.\n"
        "Get a free key at https://api.census.gov/data/key_signup.html\n"
        "Then add CENSUS_API_KEY=<your_key> to your .env file.",
        file=sys.stderr,
    )
    sys.exit(1)

ACS_YEAR = "2022"
BASE_ACS = f"https://api.census.gov/data/{ACS_YEAR}/acs/acs5"
RAW_DIR  = Path(__file__).resolve().parent.parent / "data" / "raw"

# ── Detailed-table variables (B tables) ─────────────────────────────────────
# Maps Census variable code → human-readable column name
B_VARS: dict[str, str] = {
    # Population & income
    "B01003_001E": "total_population",
    "B19013_001E": "median_household_income",
    "B01002_001E": "median_age",
    # Race / ethnicity (raw counts; % computed below)
    "B02001_002E": "pop_white_alone",
    "B02001_003E": "pop_black_alone",
    "B02001_005E": "pop_asian_alone",
    "B03002_012E": "pop_hispanic_latino",
    # Age 65+ by sex — summed below to derive pct_65_plus
    "B01001_020E": "male_65_66",
    "B01001_021E": "male_67_69",
    "B01001_022E": "male_70_74",
    "B01001_023E": "male_75_79",
    "B01001_024E": "male_80_84",
    "B01001_025E": "male_85_plus",
    "B01001_044E": "female_65_66",
    "B01001_045E": "female_67_69",
    "B01001_046E": "female_70_74",
    "B01001_047E": "female_75_79",
    "B01001_048E": "female_80_84",
    "B01001_049E": "female_85_plus",
    # Poverty
    "B17001_001E": "poverty_universe",
    "B17001_002E": "pop_below_poverty",
}

# ── Data Profile variables (DP tables) ──────────────────────────────────────
# S2701_C04_001E is the raw COUNT of uninsured people, not a percentage.
# DP03_0099PE is the pre-computed "% no health insurance coverage" — use that.
DP_VARS: dict[str, str] = {
    "DP03_0099PE": "pct_uninsured",
}

CENSUS_NULL_SENTINEL = -999_999_000  # Census uses large negative ints for suppressed/missing


def fetch_census(endpoint: str, var_codes: list[str]) -> pd.DataFrame:
    params = {
        "get": "NAME," + ",".join(var_codes),
        "for": "county:*",
        "in":  "state:*",
        "key": CENSUS_API_KEY,
    }
    resp = requests.get(endpoint, params=params, timeout=60)
    if resp.status_code == 400:
        print(f"Census API 400 error: {resp.text}", file=sys.stderr)
        resp.raise_for_status()
    resp.raise_for_status()
    data = resp.json()
    headers, rows = data[0], data[1:]
    return pd.DataFrame(rows, columns=headers)


def mask_sentinel(series: pd.Series) -> pd.Series:
    """Replace Census suppression sentinel values with NaN."""
    numeric = pd.to_numeric(series, errors="coerce")
    numeric[numeric < CENSUS_NULL_SENTINEL / 10] = None
    return numeric


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    # ── Pull 1: detailed B-tables ────────────────────────────────────────────
    print(f"Pulling ACS {ACS_YEAR} 5-Year detailed tables (B tables)...")
    df_b = fetch_census(BASE_ACS, list(B_VARS.keys()))
    print(f"  {len(df_b):,} county rows")

    # ── Pull 2: subject table S2701 (uninsured rate) ─────────────────────────
    print(f"Pulling ACS {ACS_YEAR} 5-Year data profile DP03 (% uninsured)...")
    df_dp = fetch_census(f"{BASE_ACS}/profile", list(DP_VARS.keys()))
    print(f"  {len(df_dp):,} county rows")

    # ── Build 5-digit FIPS before merging ────────────────────────────────────
    # Census returns 'state' (2-digit) and 'county' (3-digit) separately.
    # We zero-pad and concatenate to match the 5-digit locationid in PLACES data.
    for df in (df_b, df_dp):
        df["fips"] = df["state"].str.zfill(2) + df["county"].str.zfill(3)

    df = df_b.merge(
        df_dp[["fips", "DP03_0099PE"]],
        on="fips",
        how="left",
    )

    # ── Rename to human-readable columns ─────────────────────────────────────
    rename_map = {**B_VARS, **DP_VARS}
    df = df.rename(columns=rename_map)

    # ── Coerce all numeric columns and mask Census null sentinels ─────────────
    numeric_cols = list(rename_map.values())
    for col in numeric_cols:
        if col in df.columns:
            df[col] = mask_sentinel(df[col])

    # ── Derive aggregate and percentage columns ───────────────────────────────
    age65_cols = [
        "male_65_66", "male_67_69", "male_70_74", "male_75_79", "male_80_84", "male_85_plus",
        "female_65_66", "female_67_69", "female_70_74", "female_75_79", "female_80_84", "female_85_plus",
    ]
    df["pop_65_plus"] = df[age65_cols].sum(axis=1)

    df["pct_65_plus"]       = (df["pop_65_plus"]        / df["total_population"] * 100).round(2)
    df["pct_below_poverty"] = (df["pop_below_poverty"]  / df["poverty_universe"] * 100).round(2)
    df["pct_white"]         = (df["pop_white_alone"]    / df["total_population"] * 100).round(2)
    df["pct_black"]         = (df["pop_black_alone"]    / df["total_population"] * 100).round(2)
    df["pct_asian"]         = (df["pop_asian_alone"]    / df["total_population"] * 100).round(2)
    df["pct_hispanic"]      = (df["pop_hispanic_latino"]/ df["total_population"] * 100).round(2)

    # ── Tidy up column order ──────────────────────────────────────────────────
    front_cols = [
        "fips", "NAME", "state", "county",
        "total_population", "median_age", "median_household_income",
        "pct_uninsured", "pct_65_plus", "pct_below_poverty",
        "pct_white", "pct_black", "pct_asian", "pct_hispanic",
    ]
    remaining = [c for c in df.columns if c not in front_cols]
    df = df[front_cols + remaining]

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\nSummary")
    print(f"  Total rows            : {len(df):,}")
    print(f"  Unique FIPS codes     : {df['fips'].nunique():,}")
    print(f"  Null median income    : {df['median_household_income'].isna().sum()}")
    print(f"  Null pct_uninsured    : {df['pct_uninsured'].isna().sum()}")
    print(f"  Median household inc  : ${df['median_household_income'].median():,.0f}")
    print(f"  Mean pct uninsured    : {df['pct_uninsured'].mean():.1f}%")

    out_path = RAW_DIR / "acs_county_2022.csv"
    df.to_csv(out_path, index=False)
    print(f"\nSaved → {out_path}  ({len(df):,} rows x {len(df.columns)} cols)")


if __name__ == "__main__":
    main()
