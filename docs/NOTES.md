# Technical Notes

Key decisions made during the build, why they were made, and their limitations.
These are the kinds of questions that come up in technical interviews for
analytics engineering or data science roles.

---

## 1. FIPS codes as the join key (not county names)

Every join between PLACES and ACS uses the 5-digit FIPS code, never the county
name string. Reason: county names are ambiguous. There are 18 states with a
"Washington County," 17 with a "Franklin County," and names vary by data source
("St. Louis County" vs "Saint Louis County"). FIPS codes are the authoritative,
unambiguous geographic identifier used by all US federal statistical agencies.

All FIPS values are stored as zero-padded 5-character text (not integers). This
is critical: loading as integer drops the leading zero for New England states
(e.g., Connecticut's FIPS starts with "09"), breaking every downstream join
silently. The dbt staging models use `lpad(cast(locationid as text), 5, '0')`
as a defensive measure even though the source data arrives correctly zero-padded.

---

## 2. Crude prevalence vs. age-adjusted prevalence

The PLACES dataset ships both crude and age-adjusted prevalence for each
county-measure. We pull **crude prevalence only** (`datavaluetypeid = 'CrdPrv'`).

**Why crude:** Age-adjusted rates are better for comparing counties with very
different age structures (e.g., a retirement community vs. a college town).
However, pulling both types doubles the row count and requires an explicit
`datavaluetypeid` filter in every downstream query to avoid double-counting.
For a portfolio project where simplicity and correctness of the pipeline matter,
crude prevalence is the cleaner choice.

**Limitation:** Rankings and correlations in this project may partly reflect
county age structure rather than true health burden. A county with 30% of
residents over 65 will naturally have higher diabetes prevalence than one
with 15% elderly. The `pct_65_plus` field in the fact table lets users
control for this in the dashboard or SQL analysis.

---

## 3. ACS variable discovery — the wrong uninsured rate

The original script pulled `S2701_C04_001E` from the Census ACS subject table,
believing it to be the percentage of uninsured people. It returned values like
4,225 for Autauga County, AL — producing a national "mean uninsured rate" of
8,853%. `S2701_C04_001E` is the **count** of uninsured people, not a rate.

The fix was `DP03_0099PE` from the ACS data profile endpoint
(`/data/2022/acs/acs5/profile`), which returns 7.4% for Autauga County —
the actual percentage. Profile table variables with a `PE` suffix are
pre-computed percentages. The lesson: always verify Census variable labels
against `api.census.gov/data/{year}/acs/acs5/variables/{var}.json` before
assuming a field is a rate vs. a count.

---

## 4. Census null sentinel masking

The Census API returns large negative integers (`-666666666`, `-999999999`,
etc.) instead of `NULL` for suppressed or missing values — typically for
counties where the sample size is too small to produce reliable estimates.
The ACS ingestion script masks any value below `-99,000,000` as `NaN`.

One county has a suppressed `median_household_income` (null in the output).
This is expected and documented in `dim_county_demographics`. No imputation
was performed; nulls propagate through to the mart tables where they appear
as null rather than as misleading zero or average values.

---

## 5. Year misalignment across PLACES measures

The PLACES 2025 release is **not** a single-vintage dataset. Different measures
are sourced from different survey years:

- **2023 vintage:** All 35 chronic disease, health status, disability, and SDOH measures
- **2022 vintage:** Five preventive care measures: DENTAL, COLON_SCREEN, MAMMOUSE, SLEEP, TEETHLOST

This means year-over-year comparisons are impossible within a single PLACES
release — no county-measure pair has data in both 2022 and 2023. True YoY
analysis requires pulling two consecutive annual PLACES releases (e.g., PLACES
2024 and PLACES 2025) and joining them on county_fips + measure_id + year.

The dbt staging model uses `row_number() OVER (PARTITION BY county_fips, measure_id ORDER BY data_year DESC)` to select the most recent year per county-measure. This is future-proof: if a subsequent release adds a 2024 row for any measure, the staging model will automatically pick it up without a code change.

---

## 6. dbt schema naming and the generate_schema_name macro

By default, dbt constructs schema names by concatenating the target schema
from `profiles.yml` with the custom schema from `dbt_project.yml`:
`{target_schema}_{custom_schema}`. With `target: staging` and
`+schema: staging`, models land in `staging_staging` — clearly wrong.

The `macros/generate_schema_name.sql` macro overrides this behavior to use
the custom schema name directly. This is the standard community pattern
(documented in dbt's own docs) but must be added manually — it is not the
default. Without it, mart tables end up in `staging_marts`, intermediate in
`staging_intermediate`, etc.

---

## 7. PLACES county count discrepancy

PLACES reports 3,145 unique `locationid` values; ACS returns 3,222. The
extra ACS rows are territories and county-equivalents not covered by PLACES
(e.g., Puerto Rico municipios, which have ACS coverage but are not in the
PLACES county-level release). One PLACES row (`locationid = '00059'`) is a
US-level aggregate, not a county — it is excluded in the staging model.

Join coverage between the two datasets is 3,144 matched counties (99.97%),
confirmed by the validation script.

---

## 8. Python 3.14 incompatibility with dbt

The system Python was 3.14. `dbt-core 1.11` depends on `mashumaro`, which
has a known incompatibility with Python 3.14's changes to `dataclasses`.
The project uses Python 3.12 (installed via Homebrew) for the virtual
environment. This is documented in the setup steps so anyone cloning the repo
doesn't encounter a silent install failure.

---

## 9. What this project does not include

- **HRSA HPSA designations:** Available from the HRSA data warehouse but
  require non-trivial geographic crosswalks to the county level. Excluded
  to keep scope manageable; could be added as a third source in a future
  `stg_hrsa_hpsa` model.
- **Age-adjusted rates:** See note 2.
- **Multi-year trend analysis:** See note 5. Would require pulling PLACES
  2024 + 2025 and building a `fct_county_health_metrics_timeseries` model
  that preserves both years.
- **Sub-county geography:** PLACES also publishes census tract and ZIP code
  level data. County is the grain chosen here because it is the finest level
  where PLACES and ACS join cleanly on a common key (FIPS).
