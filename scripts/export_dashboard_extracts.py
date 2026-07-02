"""
Export mart tables to dashboard-ready CSV extracts.

Writes three files to data/processed/ (gitignored — regenerate any time):

  fct_county_health_metrics.csv  — full long-format fact table (114k rows)
                                    one row per county × measure; best for
                                    Tableau/Power BI with measure_id as a filter
  dim_county_demographics.csv    — county demographics dimension (3,222 rows)
                                    join to fact on county_fips
  county_health_wide.csv         — pivoted wide format (one row per county)
                                    20 key measures as individual columns;
                                    easier for users who want all measures
                                    visible without filter actions
"""

import os
import pandas as pd
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

PROCESSED_DIR = Path(__file__).resolve().parent.parent / "data" / "processed"
PG_URL = (
    f"postgresql+psycopg2://"
    f"{os.getenv('PG_USER','postgres')}:{os.getenv('PG_PASSWORD','postgres')}"
    f"@{os.getenv('PG_HOST','localhost')}:{os.getenv('PG_PORT','5432')}"
    f"/{os.getenv('PG_DB','health_dashboard')}"
)

# 20 key measures to include in the wide-format extract
WIDE_MEASURES = [
    # Chronic conditions
    "DIABETES", "OBESITY", "BPHIGH", "CHD", "STROKE",
    "COPD", "CASTHMA", "DEPRESSION", "HIGHCHOL", "ARTHRITIS",
    # Risk behaviors
    "CSMOKING", "BINGE", "LPA",
    # Preventive care
    "CHECKUP", "DENTAL", "MAMMOUSE", "COLON_SCREEN",
    # Self-reported health
    "GHLTH", "MHLTH",
    # Access & SDOH
    "ACCESS2",
]


def export_table(engine, query: str, out_path: Path, label: str) -> None:
    print(f"Exporting {label} ...")
    df = pd.read_sql(query, engine)
    df.to_csv(out_path, index=False)
    print(f"  {len(df):,} rows × {len(df.columns)} cols → {out_path.name}")


def build_wide_format(engine) -> pd.DataFrame:
    """Pivot fct to one row per county, each measure as its own column."""
    df = pd.read_sql(
        """
        SELECT
            county_fips,
            county_name,
            state_abbr,
            state_name,
            measure_id,
            prevalence_pct,
            national_pct_rank,
            -- carry through county-level fields (same for every measure row)
            total_population,
            median_household_income,
            pct_uninsured,
            pct_below_poverty,
            pct_65_plus,
            pct_white,
            pct_black,
            pct_hispanic,
            income_quartile,
            uninsured_quartile,
            poverty_quartile,
            population_size_category,
            has_acs_data
        FROM marts.fct_county_health_metrics
        WHERE has_acs_data = true
        """,
        engine,
    )

    # Pivot prevalence values
    prevalence_wide = (
        df[df["measure_id"].isin(WIDE_MEASURES)]
        .pivot_table(
            index="county_fips",
            columns="measure_id",
            values="prevalence_pct",
            aggfunc="first",
        )
        .reset_index()
    )
    prevalence_wide.columns = [
        "county_fips" if c == "county_fips" else f"prev_{c.lower()}"
        for c in prevalence_wide.columns
    ]

    # Pivot national rank values
    rank_wide = (
        df[df["measure_id"].isin(WIDE_MEASURES)]
        .pivot_table(
            index="county_fips",
            columns="measure_id",
            values="national_pct_rank",
            aggfunc="first",
        )
        .reset_index()
    )
    rank_wide.columns = [
        "county_fips" if c == "county_fips" else f"rank_{c.lower()}"
        for c in rank_wide.columns
    ]

    # Grab county-level demographic columns (one row per county)
    demo_cols = [
        "county_fips", "county_name", "state_abbr", "state_name",
        "total_population", "median_household_income", "pct_uninsured",
        "pct_below_poverty", "pct_65_plus", "pct_white", "pct_black",
        "pct_hispanic", "income_quartile", "uninsured_quartile",
        "poverty_quartile", "population_size_category",
    ]
    demo = df[demo_cols].drop_duplicates("county_fips")

    # Join everything
    wide = demo.merge(prevalence_wide, on="county_fips", how="left")
    wide = wide.merge(rank_wide, on="county_fips", how="left")

    # Add composite burden index: average of 8 core chronic conditions
    core = ["prev_diabetes", "prev_obesity", "prev_bphigh", "prev_chd",
            "prev_stroke", "prev_copd", "prev_casthma", "prev_depression"]
    available = [c for c in core if c in wide.columns]
    wide["burden_index"] = wide[available].mean(axis=1).round(2)

    return wide


def main() -> None:
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    engine = create_engine(PG_URL, future=True)

    # 1 — Full long-format fact table
    export_table(
        engine,
        "SELECT * FROM marts.fct_county_health_metrics ORDER BY county_fips, measure_id",
        PROCESSED_DIR / "fct_county_health_metrics.csv",
        "fct_county_health_metrics (long format)",
    )

    # 2 — Demographics dimension
    export_table(
        engine,
        "SELECT * FROM marts.dim_county_demographics ORDER BY county_fips",
        PROCESSED_DIR / "dim_county_demographics.csv",
        "dim_county_demographics",
    )

    # 3 — Wide / pivoted format
    print("Building wide-format pivot ...")
    wide = build_wide_format(engine)
    out = PROCESSED_DIR / "county_health_wide.csv"
    wide.to_csv(out, index=False)
    print(f"  {len(wide):,} rows × {len(wide.columns)} cols → {out.name}")

    print(f"\nAll extracts written to {PROCESSED_DIR}/")
    print("Import into Tableau or Power BI using the field guide in docs/dashboard_field_guide.md")


if __name__ == "__main__":
    main()
