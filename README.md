# Public Health Outcomes Dashboard

An end-to-end analytics pipeline transforming CDC PLACES county-level chronic disease data and US Census ACS demographic data into analysis-ready tables, a reusable SQL query library, and dashboard-ready extracts for Tableau / Power BI.

Built as a portfolio project targeting health analytics roles (CVS Health focus).

---

## Project Overview

| Layer | Tool | Purpose |
|---|---|---|
| Data sourcing | Python (`scripts/`) | Pull CDC PLACES + Census ACS via API |
| Warehouse | PostgreSQL 16 (Docker) | Store raw and modeled data |
| Transformation | dbt-core 1.11 | Staging, intermediate, and mart models |
| Query library | SQL (`sql/`) | 20 reusable analytical queries |
| Visualization | Tableau Public / Power BI | Final dashboards (built from mart exports) |

---

## Data Sources

- **CDC PLACES 2025 release** — county-level crude prevalence estimates for 40 chronic disease, behavioral, disability, and social determinant measures across 3,145 US counties  
  <https://data.cdc.gov/resource/swc5-untb>
- **US Census ACS 5-Year Estimates (2022)** — median household income, uninsured rate, age distribution, race/ethnicity, and poverty rate at the county level  
  <https://api.census.gov/data/2022/acs/acs5>

---

## Repo Structure

```
public-health-dashboard/
├── data/
│   ├── raw/          # Downloaded source files (gitignored)
│   └── processed/    # Dashboard-ready CSV extracts (gitignored)
├── dbt_project/      # dbt models, tests, macros, and docs
│   └── models/
│       ├── staging/       # stg_cdc_places, stg_acs_demographics
│       ├── intermediate/  # int_county_health_demographics
│       └── marts/         # fct_county_health_metrics, dim_county_demographics
├── sql/              # 20-query analytical SQL library
│   ├── 01_rankings.sql    # County and state disease burden rankings
│   ├── 02_correlations.sql # Income, insurance, race/ethnicity correlations
│   └── 03_trends.sql      # Window functions, outlier detection, disparity gaps
├── scripts/          # Python ingestion, load, and export scripts
├── docs/             # Field guide, insights, and technical notes
├── requirements.txt
└── README.md
```

---

## Setup

### Prerequisites

- Python 3.12 (dbt requires ≤ 3.12; Python 3.14 is incompatible with dbt-core 1.11)
- Docker
- A free Census API key: <https://api.census.gov/data/key_signup.html>

### 1. Clone and install

```bash
git clone https://github.com/johnesposito17/public-health-dashboard.git
cd public-health-dashboard
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure environment variables

```bash
cp .env.example .env
# Fill in CENSUS_API_KEY and Postgres credentials
```

### 3. Start Postgres (Docker)

```bash
docker run --name ds-health-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=health_dashboard \
  -p 5432:5432 \
  -d postgres:16
```

Connection string: `postgresql://postgres:postgres@localhost:5432/health_dashboard`

### 4. Pull raw data

```bash
python3 scripts/pull_cdc_places.py   # ~2 min; no API key needed
python3 scripts/pull_acs_data.py     # requires CENSUS_API_KEY in .env
```

### 5. Validate raw data

```bash
python3 scripts/validate_data.py     # all 8 checks should pass
```

### 6. Load into Postgres and run dbt

```bash
python3 scripts/load_to_postgres.py

# Configure dbt connection (one time)
cp dbt_project/profiles.yml.example ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml with your Postgres credentials

cd dbt_project
dbt run      # builds 5 models: 2 staging views, 1 intermediate view, 2 mart tables
dbt test     # runs 34 data quality tests
dbt docs generate && dbt docs serve   # browse lineage at localhost:8080
```

### 7. Export dashboard extracts

```bash
cd ..
python3 scripts/export_dashboard_extracts.py
# Writes 3 files to data/processed/
```

---

## What's in the mart tables

### `fct_county_health_metrics` — 114,609 rows
One row per county × health measure. Key fields:

- `county_fips`, `county_name`, `state_abbr`
- `measure_id`, `prevalence_pct`, `ci_low`, `ci_high`
- `national_pct_rank`, `state_pct_rank` — PERCENT_RANK (0–100) within each measure
- `income_quartile`, `uninsured_quartile`, `poverty_quartile` — NTILE(4) segments
- `median_household_income`, `pct_uninsured`, `pct_65_plus`, demographic breakdown

### `dim_county_demographics` — 3,222 rows
One row per county. ACS 2022 demographics with quartile classifications and a
`population_size_category` field (Rural → Metro) for dashboard filtering.

See [`docs/dashboard_field_guide.md`](docs/dashboard_field_guide.md) for the
complete field reference.

---

## SQL Query Library

20 production-quality queries in `/sql/`, all verified against the live Postgres database:

| File | Queries |
|---|---|
| `01_rankings.sql` | Top N counties, composite burden index, state rankings, high-burden/low-income targeting |
| `02_correlations.sql` | Uninsured vs. disease scatter data, income quartile breakdown, preventive care gaps, racial disparity, SDOH clustering |
| `03_trends.sql` | Cross-year dental/diabetes correlation, z-score outlier detection, within-state disparity gaps, decile distributions, cumulative population coverage, moving averages |

---

## Key Findings

1. **Income is the strongest predictor of diabetes burden.** Lowest-income counties average 16.9% diabetes prevalence vs. 11.3% in the highest-income quartile — a 49% higher burden with a monotonic gradient across all four tiers.

2. **Insurance gaps translate into preventive care deficits.** Counties with the highest uninsured rates have dental visit rates of 51% vs. 64.5% in the best-covered counties — a 13.5 percentage point gap.

3. **Rural counties carry disproportionate disease burden** despite comparable annual checkup rates, pointing to upstream social determinants rather than care avoidance as the primary driver.

4. **302 "double burden" counties** — simultaneously lowest income and highest uninsured — average 17.1% diabetes prevalence (vs. 13.6% nationally) and concentrate in Deep South states.

See [`docs/INSIGHTS.md`](docs/INSIGHTS.md) for full write-up and [`docs/NOTES.md`](docs/NOTES.md) for technical decisions.

---

## Dashboard

> **Tableau Public link:** _[placeholder — to be added after publish]_

Import the files from `data/processed/` into Tableau or Power BI.
See [`docs/dashboard_field_guide.md`](docs/dashboard_field_guide.md) for
field definitions and five suggested dashboard views.
