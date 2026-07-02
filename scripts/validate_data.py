"""
Data validation script for raw CDC PLACES and ACS county files.

Checks:
  1. File existence
  2. Null rates on key columns
  3. FIPS code format (5-digit, numeric-only, plausible state codes)
  4. PLACES: data_value in range [0, 100]
  5. ACS: income and pct fields in expected ranges
  6. Cross-dataset join coverage (% of PLACES counties with a matching ACS record)

Run after both pull scripts complete. Exits with code 1 if any hard check fails.
"""

import sys
import pandas as pd
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
PLACES_FILE = RAW_DIR / "cdc_places_county.csv"
ACS_FILE    = RAW_DIR / "acs_county_2022.csv"

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
WARN = "\033[93mWARN\033[0m"
SKIP = "\033[90mSKIP\033[0m"

failures: list[str] = []


def check(label: str, condition: bool, message: str = "", warn_only: bool = False) -> None:
    if condition:
        print(f"  [{PASS}] {label}")
    else:
        tag = WARN if warn_only else FAIL
        print(f"  [{tag}] {label}{' — ' + message if message else ''}")
        if not warn_only:
            failures.append(label)


def section(title: str) -> None:
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ── PLACES validation ────────────────────────────────────────────────────────

section("1. File existence")
places_exists = PLACES_FILE.exists()
acs_exists    = ACS_FILE.exists()
check("CDC PLACES raw file exists", places_exists, str(PLACES_FILE))
check("ACS raw file exists",        acs_exists,    str(ACS_FILE), warn_only=True)

if places_exists:
    section("2. CDC PLACES — schema & nulls")
    df_p = pd.read_csv(PLACES_FILE, dtype={"locationid": str}, low_memory=False)

    required_cols = ["year", "stateabbr", "locationid", "measureid",
                     "data_value", "datavaluetypeid", "category"]
    for col in required_cols:
        check(f"Column '{col}' present", col in df_p.columns)

    check("No duplicate county+measure rows",
          not df_p.duplicated(subset=["locationid", "measureid", "year"]).any(),
          f"{df_p.duplicated(subset=['locationid','measureid','year']).sum()} duplicates found")

    section("3. CDC PLACES — FIPS format")
    fips = df_p["locationid"].dropna()
    check("All FIPS are 5 characters",
          (fips.str.len() == 5).all(),
          f"{(fips.str.len() != 5).sum()} malformed values")
    check("All FIPS are numeric",
          fips.str.match(r"^\d{5}$").all(),
          f"{(~fips.str.match(r'^\\d{5}$')).sum()} non-numeric values")

    valid_states = set(f"{i:02d}" for i in range(1, 57) if i not in (3, 7, 14, 43, 52))
    state_codes = fips.str[:2].unique()
    bad_states = [s for s in state_codes if s not in valid_states]
    check("State portion of FIPS in valid range",
          len(bad_states) == 0,
          f"Unrecognized state codes: {bad_states}",
          warn_only=True)

    section("4. CDC PLACES — data quality")
    data_vals = pd.to_numeric(df_p["data_value"], errors="coerce")
    null_rate = data_vals.isna().mean() * 100
    check("Null data_value < 5%",
          null_rate < 5,
          f"Null rate = {null_rate:.1f}%",
          warn_only=True)
    vals_notnull = data_vals.dropna()
    out_of_range = ((vals_notnull < 0) | (vals_notnull > 100)).sum()
    check("data_value in [0, 100]",
          out_of_range == 0,
          f"{out_of_range} out-of-range values")

    n_counties = df_p["locationid"].nunique()
    n_measures = df_p["measureid"].nunique()
    print(f"\n  Info: {len(df_p):,} rows | {n_counties:,} counties | {n_measures} measures")
    print(f"  Measures: {sorted(df_p['measureid'].unique())}")
    print(f"  Years   : {sorted(df_p['year'].unique())}")

if acs_exists:
    section("5. ACS — schema & nulls")
    df_a = pd.read_csv(ACS_FILE, dtype={"fips": str})

    required_acs = ["fips", "NAME", "total_population", "median_household_income",
                    "pct_uninsured", "pct_65_plus", "pct_below_poverty"]
    for col in required_acs:
        check(f"Column '{col}' present", col in df_a.columns)

    section("6. ACS — FIPS format")
    fips_a = df_a["fips"].dropna()
    check("All ACS FIPS are 5 characters",
          (fips_a.str.len() == 5).all(),
          f"{(fips_a.str.len() != 5).sum()} malformed")
    check("All ACS FIPS are numeric",
          fips_a.str.match(r"^\d{5}$").all())

    section("7. ACS — value range checks")
    pct_cols = ["pct_uninsured", "pct_65_plus", "pct_below_poverty",
                "pct_white", "pct_black", "pct_asian", "pct_hispanic"]
    for col in pct_cols:
        if col in df_a.columns:
            s = df_a[col].dropna()
            check(f"{col} in [0, 100]",
                  ((s >= 0) & (s <= 100)).all(),
                  f"{((s < 0) | (s > 100)).sum()} out-of-range",
                  warn_only=True)

    check("median_household_income > 0 where not null",
          (df_a["median_household_income"].dropna() > 0).all())

    null_income = df_a["median_household_income"].isna().sum()
    null_unins  = df_a["pct_uninsured"].isna().sum()
    print(f"\n  Info: {len(df_a):,} county rows")
    print(f"  Null median_household_income : {null_income}")
    print(f"  Null pct_uninsured           : {null_unins}")

if places_exists and acs_exists:
    section("8. Cross-dataset join coverage")
    places_fips = set(df_p["locationid"].unique())
    acs_fips    = set(df_a["fips"].unique())

    matched       = places_fips & acs_fips
    unmatched     = places_fips - acs_fips
    coverage_pct  = len(matched) / len(places_fips) * 100

    check("Join coverage >= 98%",
          coverage_pct >= 98,
          f"Coverage = {coverage_pct:.1f}% ({len(matched):,} matched, {len(unmatched)} unmatched)",
          warn_only=True)
    print(f"\n  Matched counties  : {len(matched):,}")
    print(f"  Unmatched PLACES  : {len(unmatched)}")
    if unmatched:
        print(f"  Unmatched FIPS    : {sorted(unmatched)[:20]}")

elif places_exists and not acs_exists:
    print(f"\n  [{SKIP}] Join coverage check — ACS file not yet present")

# ── Result ───────────────────────────────────────────────────────────────────
section("Result")
if failures:
    print(f"\n  {len(failures)} hard check(s) FAILED:")
    for f in failures:
        print(f"    - {f}")
    sys.exit(1)
else:
    print(f"\n  All hard checks passed.")
