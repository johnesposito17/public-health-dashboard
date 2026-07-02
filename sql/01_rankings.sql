-- =============================================================================
-- 01_rankings.sql
-- County and state rankings by chronic disease burden
--
-- All queries run against: marts.fct_county_health_metrics
--                          marts.dim_county_demographics
-- Change the measure_id filter to swap in any of the 40 available measures.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1: Top 25 counties nationally by prevalence for a given measure
--     Useful for: dashboard "worst counties" table, heat map data prep
-- -----------------------------------------------------------------------------
SELECT
    county_fips,
    county_name,
    state_abbr,
    prevalence_pct,
    national_pct_rank,
    ci_low,
    ci_high,
    total_population,
    median_household_income,
    income_quartile
FROM marts.fct_county_health_metrics
WHERE measure_id    = 'DIABETES'   -- swap measure here
  AND has_acs_data  = true
ORDER BY prevalence_pct DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q2: Composite chronic disease burden score per county
--     Averages prevalence across the 8 core chronic conditions to produce a
--     single "burden index" for ranking. Requires all 8 measures to be present.
--     Useful for: overall health risk map, county prioritization
-- -----------------------------------------------------------------------------
WITH core_conditions AS (
    SELECT
        county_fips,
        county_name,
        state_abbr,
        total_population,
        income_quartile,
        median_household_income,
        -- pivot the 8 measures into one row per county
        MAX(CASE WHEN measure_id = 'DIABETES'   THEN prevalence_pct END) AS diabetes_pct,
        MAX(CASE WHEN measure_id = 'OBESITY'    THEN prevalence_pct END) AS obesity_pct,
        MAX(CASE WHEN measure_id = 'BPHIGH'     THEN prevalence_pct END) AS hypertension_pct,
        MAX(CASE WHEN measure_id = 'CHD'        THEN prevalence_pct END) AS heart_disease_pct,
        MAX(CASE WHEN measure_id = 'STROKE'     THEN prevalence_pct END) AS stroke_pct,
        MAX(CASE WHEN measure_id = 'COPD'       THEN prevalence_pct END) AS copd_pct,
        MAX(CASE WHEN measure_id = 'CASTHMA'    THEN prevalence_pct END) AS asthma_pct,
        MAX(CASE WHEN measure_id = 'DEPRESSION' THEN prevalence_pct END) AS depression_pct
    FROM marts.fct_county_health_metrics
    WHERE has_acs_data = true
    GROUP BY
        county_fips, county_name, state_abbr,
        total_population, income_quartile, median_household_income
),

scored AS (
    SELECT
        *,
        ROUND(
            (COALESCE(diabetes_pct, 0)     +
             COALESCE(obesity_pct, 0)      +
             COALESCE(hypertension_pct, 0) +
             COALESCE(heart_disease_pct, 0)+
             COALESCE(stroke_pct, 0)       +
             COALESCE(copd_pct, 0)         +
             COALESCE(asthma_pct, 0)       +
             COALESCE(depression_pct, 0))
            / NULLIF(
                (CASE WHEN diabetes_pct    IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN obesity_pct     IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN hypertension_pct IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN heart_disease_pct IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN stroke_pct      IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN copd_pct        IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN asthma_pct      IS NOT NULL THEN 1 ELSE 0 END +
                 CASE WHEN depression_pct  IS NOT NULL THEN 1 ELSE 0 END), 0),
            2
        ) AS burden_index
    FROM core_conditions
)

SELECT
    county_fips,
    county_name,
    state_abbr,
    burden_index,
    RANK() OVER (ORDER BY burden_index DESC) AS national_burden_rank,
    total_population,
    median_household_income,
    income_quartile,
    diabetes_pct,
    obesity_pct,
    hypertension_pct
FROM scored
WHERE burden_index IS NOT NULL
ORDER BY burden_index DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- Q3: State rankings — average disease burden across counties
--     Useful for: state comparison bar chart, geographic performance overview
-- -----------------------------------------------------------------------------
SELECT
    state_abbr,
    COUNT(DISTINCT county_fips)                   AS county_count,
    ROUND(AVG(prevalence_pct), 2)                 AS avg_prevalence_pct,
    ROUND(PERCENTILE_CONT(0.5)
          WITHIN GROUP (ORDER BY prevalence_pct)::NUMERIC, 2)
                                                  AS median_prevalence_pct,
    ROUND(MIN(prevalence_pct), 2)                 AS min_prevalence_pct,
    ROUND(MAX(prevalence_pct), 2)                 AS max_prevalence_pct,
    ROUND(MAX(prevalence_pct) - MIN(prevalence_pct), 2)
                                                  AS within_state_range,
    RANK() OVER (ORDER BY AVG(prevalence_pct) DESC) AS state_burden_rank
FROM marts.fct_county_health_metrics
WHERE measure_id   = 'DIABETES'   -- swap measure here
  AND has_acs_data = true
  AND state_abbr  != 'US'
GROUP BY state_abbr
ORDER BY avg_prevalence_pct DESC;


-- -----------------------------------------------------------------------------
-- Q4: County rankings within a specific state
--     Useful for: state-scoped dashboard page, regional planning tool
-- -----------------------------------------------------------------------------
SELECT
    county_fips,
    county_name,
    prevalence_pct,
    state_pct_rank,
    national_pct_rank,
    median_household_income,
    pct_uninsured,
    income_quartile
FROM marts.fct_county_health_metrics
WHERE measure_id = 'DIABETES'   -- swap measure here
  AND state_abbr = 'MS'         -- swap state here (Mississippi = highest diabetes burden)
ORDER BY prevalence_pct DESC;


-- -----------------------------------------------------------------------------
-- Q5: High-burden, low-income counties — the hardest-hit populations
--     Identifies counties simultaneously in the worst quartile for disease
--     burden AND the lowest income quartile. High-value for targeting
--     interventions or retail pharmacy site selection (CVS context).
-- -----------------------------------------------------------------------------
SELECT
    f.county_fips,
    f.county_name,
    f.state_abbr,
    f.prevalence_pct,
    f.national_pct_rank,
    f.median_household_income,
    f.pct_uninsured,
    f.pct_below_poverty,
    f.income_quartile,
    f.uninsured_quartile,
    f.total_population,
    d.population_size_category
FROM marts.fct_county_health_metrics f
JOIN marts.dim_county_demographics   d USING (county_fips)
WHERE f.measure_id        = 'DIABETES'
  AND f.income_quartile   = 1           -- lowest income counties
  AND f.national_pct_rank >= 75         -- worst 25% nationally for diabetes
  AND f.has_acs_data      = true
ORDER BY f.prevalence_pct DESC;


-- -----------------------------------------------------------------------------
-- Q6: Measure-level national summary statistics
--     At-a-glance overview of the full distribution for each measure.
--     Useful for: executive summary slide, measure selection for dashboards
-- -----------------------------------------------------------------------------
SELECT
    measure_id,
    measure_short,
    measure_category,
    COUNT(DISTINCT county_fips)                                  AS counties_with_data,
    ROUND(AVG(prevalence_pct), 2)                                AS national_avg_pct,
    ROUND(PERCENTILE_CONT(0.5)
          WITHIN GROUP (ORDER BY prevalence_pct)::NUMERIC, 2)    AS national_median_pct,
    ROUND(PERCENTILE_CONT(0.1)
          WITHIN GROUP (ORDER BY prevalence_pct)::NUMERIC, 2)    AS p10_pct,
    ROUND(PERCENTILE_CONT(0.9)
          WITHIN GROUP (ORDER BY prevalence_pct)::NUMERIC, 2)    AS p90_pct,
    ROUND(MAX(prevalence_pct) - MIN(prevalence_pct), 2)          AS national_range
FROM marts.fct_county_health_metrics
WHERE has_acs_data = true
GROUP BY measure_id, measure_short, measure_category
ORDER BY national_avg_pct DESC;
