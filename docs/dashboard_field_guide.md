# Dashboard Field Guide

This guide documents every field in the three CSV extracts in `data/processed/`.
Use it as your reference when building Tableau or Power BI dashboards.

Regenerate the extracts any time by running:
```bash
python3 scripts/export_dashboard_extracts.py
```

---

## Which file to use?

| File | Rows | Best for |
|---|---|---|
| `fct_county_health_metrics.csv` | ~114,600 | Any dashboard that filters by measure (Tableau Parameter Actions, PBI slicers) |
| `dim_county_demographics.csv` | 3,222 | Demographic reference; join to fact on `county_fips` |
| `county_health_wide.csv` | 3,144 | Scatter plots, correlation views, calculated fields across measures |

---

## fct_county_health_metrics.csv

**Grain:** one row per county × health measure. Filter `measure_id` to scope to one condition.

### Geography
| Field | Type | Description |
|---|---|---|
| `county_fips` | text | 5-digit FIPS code, zero-padded. Primary join key. Use this — never join on county name, which is ambiguous across states. |
| `county_name` | text | County name without state (e.g. "Autauga County"). |
| `state_abbr` | text | Two-letter postal abbreviation (e.g. "AL"). |
| `state_name` | text | Full state name (e.g. "Alabama"). |

### Measure metadata
| Field | Type | Description |
|---|---|---|
| `measure_id` | text | Short code identifying the health measure. See the full list below. |
| `measure_name` | text | Full CDC measure description (e.g. "Diagnosed diabetes among adults"). |
| `measure_short` | text | Abbreviated label for chart axes (e.g. "Diabetes"). |
| `measure_category` | text | CDC category: "Health Outcomes", "Prevention", "Health Risk Behaviors", "Health Status", "Disability", "Social Determinants". |
| `data_year` | integer | Survey year the estimate is drawn from. 2023 for most measures; 2022 for DENTAL, COLON_SCREEN, MAMMOUSE, SLEEP, TEETHLOST. |

### Prevalence
| Field | Type | Description |
|---|---|---|
| `prevalence_pct` | numeric | Crude prevalence as a percentage (0–100). The core metric. |
| `ci_low` | numeric | Lower bound of the 95% confidence interval. |
| `ci_high` | numeric | Upper bound of the 95% confidence interval. |

### Population denominators
| Field | Type | Description |
|---|---|---|
| `total_population` | integer | Total county population (ACS B01003). Use as bubble size. |
| `population_18_plus` | integer | Adult (18+) population — the denominator for most PLACES measures. |

### Demographic context (from ACS)
| Field | Type | Description |
|---|---|---|
| `median_household_income` | integer | Median household income in past 12 months (2022 dollars). Null for ~1 suppressed county. |
| `pct_uninsured` | numeric | % of civilian noninstitutionalized population with no health insurance. |
| `pct_below_poverty` | numeric | % of population below the federal poverty line. |
| `pct_65_plus` | numeric | % of population aged 65 or older. |
| `median_age` | numeric | Median age of county population. |
| `pct_white` | numeric | % identifying as White alone (non-Hispanic). |
| `pct_black` | numeric | % identifying as Black or African American alone. |
| `pct_asian` | numeric | % identifying as Asian alone. |
| `pct_hispanic` | numeric | % identifying as Hispanic or Latino (any race). |

### Rankings
| Field | Type | Description |
|---|---|---|
| `national_pct_rank` | numeric | Percentile rank (0–100) within the measure across all US counties. **100 = worst nationally.** Use for "this county ranks in the Xth percentile" callouts. |
| `state_pct_rank` | numeric | Same, but ranked only within the county's state. Useful for within-state map layers. |

### Quartile segments
All quartiles use `NTILE(4)` computed at the county grain. **1 = best (lowest burden / lowest risk), 4 = worst.**

| Field | Type | Description |
|---|---|---|
| `income_quartile` | integer (1–4) | 1 = lowest-income counties, 4 = highest-income. |
| `uninsured_quartile` | integer (1–4) | 1 = lowest uninsured rate, 4 = highest. |
| `poverty_quartile` | integer (1–4) | 1 = lowest poverty rate, 4 = highest. |
| `population_quartile` | integer (1–4) | 1 = smallest counties, 4 = largest. |
| `population_size_category` | text | Human-readable tier: Rural (<25k), Small (25k–100k), Mid-size (100k–500k), Large (500k–1M), Metro (1M+). |

### Data quality
| Field | Type | Description |
|---|---|---|
| `has_acs_data` | boolean | `true` for ~3,144 counties matched to ACS. `false` for one unmatched territory row. Filter to `true` for all demographic analysis. |

---

## dim_county_demographics.csv

**Grain:** one row per county. Join to the fact on `county_fips`.

Contains the same demographic fields as the fact table, plus:

| Field | Type | Description |
|---|---|---|
| `acs_year` | integer | ACS estimate vintage (2022). |
| `state_fips` | text | 2-digit state FIPS code. |
| `pop_white_alone` | integer | Raw count (not %). Use for custom rate calculations. |
| `pop_black_alone` | integer | Raw count. |
| `pop_asian_alone` | integer | Raw count. |
| `pop_hispanic_latino` | integer | Raw count. |
| `pop_65_plus` | integer | Raw count of population 65+. |

All quartile and tier fields from the fact table are also present here.

---

## county_health_wide.csv

**Grain:** one row per county. 57 columns.

Each of the 20 key measures appears as two columns — `prev_<measure>` (prevalence %) and `rank_<measure>` (national percentile rank).

### Measure columns included

| Prefix | Measure |
|---|---|
| `prev_diabetes` / `rank_diabetes` | Diagnosed diabetes among adults |
| `prev_obesity` / `rank_obesity` | Obesity among adults |
| `prev_bphigh` / `rank_bphigh` | High blood pressure |
| `prev_chd` / `rank_chd` | Coronary heart disease |
| `prev_stroke` / `rank_stroke` | Stroke |
| `prev_copd` / `rank_copd` | COPD |
| `prev_casthma` / `rank_casthma` | Current asthma |
| `prev_depression` / `rank_depression` | Depression |
| `prev_highchol` / `rank_highchol` | High cholesterol |
| `prev_arthritis` / `rank_arthritis` | Arthritis |
| `prev_csmoking` / `rank_csmoking` | Current cigarette smoking |
| `prev_binge` / `rank_binge` | Binge drinking |
| `prev_lpa` / `rank_lpa` | Physical inactivity (no leisure-time activity) |
| `prev_checkup` / `rank_checkup` | Annual checkup (2023) |
| `prev_dental` / `rank_dental` | Dental visit (2022) |
| `prev_mammouse` / `rank_mammouse` | Mammography use (2022) |
| `prev_colon_screen` / `rank_colon_screen` | Colorectal cancer screening (2022) |
| `prev_ghlth` / `rank_ghlth` | Fair or poor self-rated health |
| `prev_mhlth` / `rank_mhlth` | Frequent mental distress (≥14 bad days/month) |
| `prev_access2` / `rank_access2` | No health insurance (ages 18–64) |

### Derived field
| Field | Description |
|---|---|
| `burden_index` | Average prevalence across 8 core chronic conditions (diabetes, obesity, hypertension, CHD, stroke, COPD, asthma, depression). Null if any of the 8 measures is missing for that county. |

---

## Full measure ID reference

| Measure ID | Description | Category | Year |
|---|---|---|---|
| ACCESS2 | No health insurance among adults 18–64 | Prevention | 2023 |
| ARTHRITIS | Arthritis among adults | Health Outcomes | 2023 |
| BINGE | Binge drinking among adults | Health Risk Behaviors | 2023 |
| BPHIGH | High blood pressure among adults | Health Outcomes | 2023 |
| BPMED | Taking BP medication among adults with hypertension | Prevention | 2023 |
| CANCER | Cancer (non-skin) or melanoma | Health Outcomes | 2023 |
| CASTHMA | Current asthma among adults | Health Outcomes | 2023 |
| CHD | Coronary heart disease among adults | Health Outcomes | 2023 |
| CHECKUP | Annual checkup among adults | Prevention | 2023 |
| CHOLSCREEN | Cholesterol screening among adults | Prevention | 2023 |
| COGNITION | Cognitive disability among adults | Disability | 2023 |
| COLON_SCREEN | Colorectal cancer screening | Prevention | **2022** |
| COPD | COPD among adults | Health Outcomes | 2023 |
| CSMOKING | Current cigarette smoking among adults | Health Risk Behaviors | 2023 |
| DENTAL | Dental visit in past year | Prevention | **2022** |
| DEPRESSION | Depression among adults | Health Outcomes | 2023 |
| DIABETES | Diagnosed diabetes among adults | Health Outcomes | 2023 |
| DISABILITY | Any disability among adults | Disability | 2023 |
| EMOTIONSPT | Lack of social/emotional support | Social Determinants | 2023 |
| FOODINSECU | Food insecurity | Social Determinants | 2023 |
| FOODSTAMP | Food stamp/SNAP use | Social Determinants | 2023 |
| GHLTH | Fair or poor self-rated health | Health Status | 2023 |
| HEARING | Hearing disability | Disability | 2023 |
| HIGHCHOL | High cholesterol among adults | Health Outcomes | 2023 |
| HOUSINSECU | Housing insecurity | Social Determinants | 2023 |
| INDEPLIVE | Independent living disability | Disability | 2023 |
| LACKTRPT | Transportation barriers | Social Determinants | 2023 |
| LONELINESS | Loneliness among adults | Social Determinants | 2023 |
| LPA | No leisure-time physical activity | Health Risk Behaviors | 2023 |
| MAMMOUSE | Mammography use among women | Prevention | **2022** |
| MHLTH | Frequent mental distress (≥14 days) | Health Status | 2023 |
| MOBILITY | Mobility disability | Disability | 2023 |
| OBESITY | Obesity among adults | Health Risk Behaviors | 2023 |
| PHLTH | Frequent physical distress (≥14 days) | Health Status | 2023 |
| SELFCARE | Self-care disability | Disability | 2023 |
| SHUTUTILITY | Utility services threat | Social Determinants | 2023 |
| SLEEP | Short sleep duration (<7 hours) | Health Risk Behaviors | **2022** |
| STROKE | Stroke among adults | Health Outcomes | 2023 |
| TEETHLOST | All teeth lost (adults 65+) | Health Outcomes | **2022** |
| VISION | Vision disability | Disability | 2023 |

---

## Suggested dashboard views

### 1 — National chronic disease map
- **File:** `fct_county_health_metrics.csv`
- **Viz:** Filled county map, color = `prevalence_pct`
- **Filter:** `measure_id` parameter (start with DIABETES)
- **Tooltip:** `county_name`, `prevalence_pct`, `national_pct_rank`, `median_household_income`

### 2 — Income quartile × disease burden bar chart
- **File:** `fct_county_health_metrics.csv`
- **Viz:** Grouped bar, X = `income_quartile`, Y = avg `prevalence_pct`, color = `measure_id`
- **Filter:** limit to 4–5 core measures for readability

### 3 — Uninsured rate vs. prevalence scatter
- **File:** `county_health_wide.csv`
- **Viz:** Scatter, X = `pct_uninsured`, Y = `prev_diabetes`, size = `total_population`, color = `income_quartile`
- **Add:** regression trend line

### 4 — State comparison table
- **File:** `fct_county_health_metrics.csv`
- **Viz:** Bar or ranked table, aggregated to state level with AVG `prevalence_pct`
- **Filter:** `measure_id`

### 5 — County deep-dive (state filter)
- **File:** `fct_county_health_metrics.csv` + `dim_county_demographics.csv`
- **Viz:** Multi-measure bar chart for selected county vs state avg vs national avg
- **Requires:** a state filter, then county selector
