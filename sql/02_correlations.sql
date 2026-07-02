-- =============================================================================
-- 02_correlations.sql
-- Demographic and socioeconomic correlations with health outcomes
--
-- These queries surface the relationship between insurance coverage, income,
-- poverty, race/ethnicity, and chronic disease burden across US counties.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q7: Uninsured rate vs. diabetes prevalence — scatter plot data
--     Produces one row per county suitable for a scatter chart in Tableau.
--     Add a trend line in the viz layer to show the correlation direction.
-- -----------------------------------------------------------------------------
SELECT
    county_fips,
    county_name,
    state_abbr,
    prevalence_pct              AS diabetes_prevalence_pct,
    pct_uninsured,
    median_household_income,
    total_population,
    population_size_category,
    income_quartile,
    uninsured_quartile
FROM marts.fct_county_health_metrics
WHERE measure_id   = 'DIABETES'
  AND has_acs_data = true
ORDER BY pct_uninsured DESC;


-- -----------------------------------------------------------------------------
-- Q8: Income quartile breakdown of disease burden across all core measures
--     Shows how prevalence climbs as income falls — the central equity story.
--     Useful for: grouped bar chart income quartile × disease measure
-- -----------------------------------------------------------------------------
SELECT
    income_quartile,
    measure_id,
    measure_short,
    COUNT(DISTINCT county_fips)            AS county_count,
    ROUND(AVG(prevalence_pct), 2)          AS avg_prevalence_pct,
    ROUND(STDDEV(prevalence_pct)::NUMERIC, 2) AS stddev_prevalence
FROM marts.fct_county_health_metrics
WHERE measure_id IN (
        'DIABETES', 'OBESITY', 'BPHIGH', 'CHD',
        'STROKE', 'COPD', 'DEPRESSION', 'CASTHMA'
    )
  AND has_acs_data   = true
  AND income_quartile IS NOT NULL
GROUP BY income_quartile, measure_id, measure_short
ORDER BY measure_id, income_quartile;


-- -----------------------------------------------------------------------------
-- Q9: Preventive care access by insurance coverage quartile
--     Tests the hypothesis: higher uninsured rates → lower preventive screening.
--     CHECKUP = annual checkup, DENTAL = dental visit, MAMMOUSE = mammography,
--     COLON_SCREEN = colorectal screening.
-- -----------------------------------------------------------------------------
SELECT
    uninsured_quartile,
    ROUND(AVG(CASE WHEN measure_id = 'CHECKUP'      THEN prevalence_pct END), 2) AS avg_annual_checkup_pct,
    ROUND(AVG(CASE WHEN measure_id = 'DENTAL'       THEN prevalence_pct END), 2) AS avg_dental_visit_pct,
    ROUND(AVG(CASE WHEN measure_id = 'MAMMOUSE'     THEN prevalence_pct END), 2) AS avg_mammography_pct,
    ROUND(AVG(CASE WHEN measure_id = 'COLON_SCREEN' THEN prevalence_pct END), 2) AS avg_colorectal_screen_pct,
    ROUND(AVG(CASE WHEN measure_id = 'CHOLSCREEN'   THEN prevalence_pct END), 2) AS avg_cholesterol_screen_pct,
    COUNT(DISTINCT county_fips)                                                  AS county_count
FROM marts.fct_county_health_metrics
WHERE measure_id IN ('CHECKUP', 'DENTAL', 'MAMMOUSE', 'COLON_SCREEN', 'CHOLSCREEN')
  AND has_acs_data       = true
  AND uninsured_quartile IS NOT NULL
GROUP BY uninsured_quartile
ORDER BY uninsured_quartile;


-- -----------------------------------------------------------------------------
-- Q10: Double burden — counties with both high uninsured AND high disease rates
--      Identifies counties in the worst quartile for BOTH access and outcomes.
--      The intersection of Q4 uninsured + Q4 disease burden is the most acute
--      need population. Especially relevant for pharmacy access planning.
-- -----------------------------------------------------------------------------
SELECT
    county_fips,
    county_name,
    state_abbr,
    prevalence_pct          AS diabetes_prevalence_pct,
    pct_uninsured,
    pct_below_poverty,
    median_household_income,
    total_population,
    population_size_category,
    national_pct_rank
FROM marts.fct_county_health_metrics
WHERE measure_id         = 'DIABETES'
  AND uninsured_quartile = 4     -- highest uninsured counties
  AND income_quartile    = 1     -- lowest income counties
  AND has_acs_data       = true
ORDER BY prevalence_pct DESC;


-- -----------------------------------------------------------------------------
-- Q11: Race/ethnicity and chronic disease burden
--      Compares counties by racial composition to surface disparities.
--      Buckets counties by majority-minority status using the largest
--      single racial/ethnic group.
-- -----------------------------------------------------------------------------
WITH county_demographics AS (
    SELECT
        county_fips,
        CASE
            WHEN pct_hispanic >= 50 THEN 'Majority Hispanic'
            WHEN pct_black    >= 30 THEN 'High Black share (≥30%)'
            WHEN pct_white    >= 75 THEN 'Majority White (≥75%)'
            ELSE 'Mixed / Other'
        END AS racial_composition_group
    FROM marts.dim_county_demographics
)

SELECT
    d.racial_composition_group,
    COUNT(DISTINCT f.county_fips)         AS county_count,
    ROUND(AVG(CASE WHEN f.measure_id = 'DIABETES'    THEN f.prevalence_pct END), 2) AS avg_diabetes_pct,
    ROUND(AVG(CASE WHEN f.measure_id = 'OBESITY'     THEN f.prevalence_pct END), 2) AS avg_obesity_pct,
    ROUND(AVG(CASE WHEN f.measure_id = 'BPHIGH'      THEN f.prevalence_pct END), 2) AS avg_hypertension_pct,
    ROUND(AVG(CASE WHEN f.measure_id = 'ACCESS2'     THEN f.prevalence_pct END), 2) AS avg_no_insurance_pct,
    ROUND(AVG(f.median_household_income), 0)                                         AS avg_median_income,
    ROUND(AVG(f.pct_uninsured), 2)                                                   AS avg_pct_uninsured
FROM marts.fct_county_health_metrics f
JOIN county_demographics            d USING (county_fips)
WHERE f.measure_id IN ('DIABETES', 'OBESITY', 'BPHIGH', 'ACCESS2')
  AND f.has_acs_data = true
GROUP BY d.racial_composition_group
ORDER BY avg_diabetes_pct DESC;


-- -----------------------------------------------------------------------------
-- Q12: Urban vs. rural health outcomes by population size tier
--      Tests whether rural counties have worse outcomes than metro counties
--      after accounting for the full range of health measures.
-- -----------------------------------------------------------------------------
SELECT
    population_size_category,
    COUNT(DISTINCT county_fips)                                                AS county_count,
    ROUND(AVG(CASE WHEN measure_id = 'DIABETES'    THEN prevalence_pct END), 2) AS avg_diabetes_pct,
    ROUND(AVG(CASE WHEN measure_id = 'OBESITY'     THEN prevalence_pct END), 2) AS avg_obesity_pct,
    ROUND(AVG(CASE WHEN measure_id = 'CSMOKING'    THEN prevalence_pct END), 2) AS avg_smoking_pct,
    ROUND(AVG(CASE WHEN measure_id = 'LPA'         THEN prevalence_pct END), 2) AS avg_no_exercise_pct,
    ROUND(AVG(CASE WHEN measure_id = 'DEPRESSION'  THEN prevalence_pct END), 2) AS avg_depression_pct,
    ROUND(AVG(CASE WHEN measure_id = 'CHECKUP'     THEN prevalence_pct END), 2) AS avg_annual_checkup_pct,
    ROUND(AVG(median_household_income), 0)                                     AS avg_median_income,
    ROUND(AVG(pct_uninsured), 2)                                               AS avg_pct_uninsured
FROM marts.fct_county_health_metrics
WHERE measure_id IN ('DIABETES','OBESITY','CSMOKING','LPA','DEPRESSION','CHECKUP')
  AND has_acs_data           = true
  AND population_size_category IS NOT NULL
GROUP BY population_size_category
ORDER BY
    CASE population_size_category
        WHEN 'Rural (<25k)'          THEN 1
        WHEN 'Small (25k–100k)'      THEN 2
        WHEN 'Mid-size (100k–500k)'  THEN 3
        WHEN 'Large (500k–1M)'       THEN 4
        WHEN 'Metro (1M+)'           THEN 5
    END;


-- -----------------------------------------------------------------------------
-- Q13: Social determinants cluster — food insecurity, housing, transportation
--      PLACES 2025 added social determinant measures. This query surfaces
--      counties where multiple social risk factors co-occur.
-- -----------------------------------------------------------------------------
WITH sdoh_pivot AS (
    SELECT
        county_fips,
        county_name,
        state_abbr,
        total_population,
        income_quartile,
        median_household_income,
        MAX(CASE WHEN measure_id = 'FOODINSECU'  THEN prevalence_pct END) AS food_insecurity_pct,
        MAX(CASE WHEN measure_id = 'HOUSINSECU'  THEN prevalence_pct END) AS housing_insecurity_pct,
        MAX(CASE WHEN measure_id = 'LACKTRPT'    THEN prevalence_pct END) AS lack_transport_pct,
        MAX(CASE WHEN measure_id = 'LONELINESS'  THEN prevalence_pct END) AS loneliness_pct,
        MAX(CASE WHEN measure_id = 'DIABETES'    THEN prevalence_pct END) AS diabetes_pct,
        MAX(CASE WHEN measure_id = 'DEPRESSION'  THEN prevalence_pct END) AS depression_pct
    FROM marts.fct_county_health_metrics
    WHERE has_acs_data = true
    GROUP BY county_fips, county_name, state_abbr,
             total_population, income_quartile, median_household_income
)

SELECT
    *,
    ROUND(
        (COALESCE(food_insecurity_pct, 0) +
         COALESCE(housing_insecurity_pct, 0) +
         COALESCE(lack_transport_pct, 0)) / 3.0,
        2
    ) AS avg_sdoh_burden
FROM sdoh_pivot
WHERE food_insecurity_pct  IS NOT NULL
  AND housing_insecurity_pct IS NOT NULL
ORDER BY avg_sdoh_burden DESC
LIMIT 50;
