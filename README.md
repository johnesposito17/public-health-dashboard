# Public Health Outcomes Dashboard

An end-to-end analytics pipeline transforming CDC PLACES county-level chronic disease data and US Census ACS demographic data into analysis-ready tables, a reusable SQL query library, and dashboard-ready extracts for Tableau.


---

## Project Overview

| Layer | Tool | Purpose |
|---|---|---|
| Data sourcing | Python (`scripts/`) | Pull CDC PLACES + Census ACS via API |
| Warehouse | PostgreSQL | Store raw and modeled data |
| Transformation | dbt-core | Staging, intermediate, and mart models |
| Query library | SQL (`sql/`) | 15–20 reusable analytical queries |
| Visualization | Tableau Public / Power BI | Final dashboards (built from mart exports) |

---

## Data Sources

- **CDC PLACES** — county-level prevalence estimates for 30+ chronic disease measures  
  <https://www.cdc.gov/places>
- **US Census ACS 5-Year Estimates** — median household income, uninsured rate, age distribution at the county level  
  <https://www.census.gov/data/developers/data-sets/acs-5year.html>
- **HRSA HPSA** (optional) — Health Professional Shortage Area designations

---

## Repo Structure

```
public-health-dashboard/
├── data/
│   ├── raw/          # Downloaded source files (gitignored)
│   └── processed/    # Cleaned extracts (gitignored)
├── dbt_project/      # dbt models, tests, and docs
├── sql/              # Standalone analytical SQL query library
├── scripts/          # Python ingestion and validation scripts
├── notebooks/        # EDA and validation notebooks
├── docs/             # Field guide, insights write-up, technical notes
├── requirements.txt
└── README.md
```

---

## Setup

### Prerequisites

- Python 3.11+
- PostgreSQL 15+ (local install or Docker)
- A free Census API key: <https://api.census.gov/data/key_signup.html>

### 1. Clone and install

```bash
git clone <repo-url>
cd public-health-dashboard
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure environment variables

Copy the example and fill in your values:

```bash
cp .env.example .env
# Edit .env — set CENSUS_API_KEY and Postgres credentials
```

`.env` is gitignored. See `.env.example` for all required variables.

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
python3 scripts/pull_cdc_places.py   # no API key needed
python3 scripts/pull_acs_data.py     # requires CENSUS_API_KEY in .env
```

### 5. Load into Postgres and run dbt

```bash
python3 scripts/load_to_postgres.py  # loads raw schema; skips ACS if file absent
cd dbt_project
dbt deps
dbt run
dbt test
dbt docs generate && dbt docs serve
```

---

## Dashboard

> **Tableau Public link:** _[placeholder — to be added after publish]_

The `/data/processed/` folder contains CSV extracts of the mart tables ready to import into Tableau or Power BI. See `docs/dashboard_field_guide.md` for field definitions.

---

## Key Findings

See [`docs/INSIGHTS.md`](docs/INSIGHTS.md) for a summary of analytical findings.

---

## Technical Notes

See [`docs/NOTES.md`](docs/NOTES.md) for decisions on FIPS code handling, missing data strategy, and join logic.
