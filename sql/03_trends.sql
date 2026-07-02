-- =============================================================================
-- 03_trends.sql
-- Window functions, year-over-year trends, and disparity analysis
--
-- Note on multi-year data: the mart tables deduplicate to the most recent year
-- per county × measure. Queries that compare 2022 vs 2023 read from the raw
-- source table (raw.cdc_places_county) directly.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q14: Cross-year correlation — 2022 preventive care vs. 2023 chronic disease
--
--      NOTE ON DATA AVAILABILITY: The PLACES 2025 release does NOT provide
--      two years of data for the same measure. Five measures are 2022 vintage
--      (DENTAL, COLON_SCREEN, MAMMOUSE, SLEEP, TEETHLOST); all others are 2023.
--      True YoY comparison is not available from a single PLACES release —
--      it requires pulling consecutive annual releases (e.g. 2024 + 2025).
--
--      Instead, this query joins 2022 preventive care rates with 2023 chronic
--      disease rates at the county level. It is a cross-measure correlation,
--      not a true temporal trend, but it surfaces a meaningful hypothesis:
--      counties with lower preventive care utilization in 2022 tend to have
--      higher chronic disease burden in 2023.
-- -----------------------------------------------------------------------------
WITH preventive AS (
    -- 2022 preventive care measures
    SELECT
        locationid                      AS county_fips,
        cast(data_value AS numeric)     AS dental_visit_pct
    FROM raw.cdc_places_county
    WHERE measureid       = 'DENTAL'
      AND datavaluetypeid = 'CrdPrv'
      AND locationid     != '00059'
      AND data_value      IS NOT NULL
),

chronic AS (
    -- 2023 chronic disease measures
    SELECT
        county_fips,
        county_name,
        state_abbr,
        prevalence_pct                  AS diabetes_pct,
        median_household_income,
        pct_uninsured,
        income_quartile,
        total_population
    FROM marts.fct_county_health_metrics
    WHERE measure_id   = 'DIABETES'
      AND has_acs_data = true
)

SELECT
    c.county_fips,
    c.county_name,
    c.state_abbr,
    p.dental_visit_pct,
    c.diabetes_pct,
    c.median_household_income,
    c.pct_uninsured,
    c.income_quartile,
    c.total_population,
    -- counties with dental access well below the national median stand out
    CASE
        WHEN p.dental_visit_pct < 50 THEN 'Very low dental access (<50%)'
        WHEN p.dental_visit_pct < 60 THEN 'Low dental access (50–60%)'
        WHEN p.dental_visit_pct < 70 THEN 'Moderate dental access (60–70%)'
        ELSE 'Higher dental access (70%+)'
    END AS dental_access_tier
FROM chronic  c
JOIN preventive p ON c.county_fips = p.county_fips
ORDER BY p.dental_visit_pct ASC;


-- -----------------------------------------------------------------------------
-- Q15: County outlier detection — flagging counties ≥ 1.5 SD above state mean
--      For a given measure, identifies counties that are statistical outliers
--      within their own state. These are the highest-need pockets even in
--      otherwise healthy states.
--      Useful for: anomaly flagging layer on a state map
-- -----------------------------------------------------------------------------
WITH state_stats AS (
    SELECT
        state_abbr,
        measure_id,
        AVG(prevalence_pct)             AS state_mean,
        STDDEV(prevalence_pct)          AS state_stddev
    FROM marts.fct_county_health_metrics
    WHERE measure_id   = 'DIABETES'
      AND has_acs_data = true
      AND state_abbr  != 'US'
    GROUP BY state_abbr, measure_id
)

SELECT
    f.county_fips,
    f.county_name,
    f.state_abbr,
    f.prevalence_pct,
    ROUND(s.state_mean::NUMERIC, 2)     AS state_avg_pct,
    ROUND(s.state_stddev::NUMERIC, 2)   AS state_stddev,
    ROUND(
        (f.prevalence_pct - s.state_mean) / NULLIF(s.state_stddev, 0),
        2
    )                                   AS z_score,
    f.median_household_income,
    f.pct_uninsured,
    f.total_population
FROM marts.fct_county_health_metrics f
JOIN state_stats s
    ON f.state_abbr  = s.state_abbr
   AND f.measure_id  = s.measure_id
WHERE f.has_acs_data = true
  AND (f.prevalence_pct - s.state_mean) / NULLIF(s.state_stddev, 0) >= 1.5
ORDER BY z_score DESC;


-- -----------------------------------------------------------------------------
-- Q16: Within-state disparity score
--      For each state × measure, computes the gap between the worst and best
--      county. A large gap = high internal inequality. States with large gaps
--      may have pockets of need even if their average looks acceptable.
-- -----------------------------------------------------------------------------
SELECT
    state_abbr,
    measure_id,
    measure_short,
    COUNT(DISTINCT county_fips)                          AS county_count,
    ROUND(MIN(prevalence_pct), 2)                        AS best_county_pct,
    ROUND(MAX(prevalence_pct), 2)                        AS worst_county_pct,
    ROUND(MAX(prevalence_pct) - MIN(prevalence_pct), 2)  AS disparity_gap,
    ROUND(AVG(prevalence_pct), 2)                        AS state_avg_pct,
    ROUND(STDDEV(prevalence_pct)::NUMERIC, 2)            AS stddev_pct,
    -- which county is worst within the state?
    MAX(county_name) FILTER (
        WHERE prevalence_pct = MAX(prevalence_pct) OVER (
            PARTITION BY state_abbr, measure_id
        )
    )                                                    AS worst_county_name
FROM marts.fct_county_health_metrics
WHERE measure_id   = 'DIABETES'
  AND has_acs_data = true
  AND state_abbr  != 'US'
GROUP BY state_abbr, measure_id, measure_short
HAVING COUNT(DISTINCT county_fips) >= 5   -- exclude states with too few counties for meaningful disparity
ORDER BY disparity_gap DESC;


-- -----------------------------------------------------------------------------
-- Q17: Percentile rank distribution — decile buckets for any measure
--      Groups counties into 10 equal buckets by national rank.
--      Useful for: distribution histogram in Tableau
-- -----------------------------------------------------------------------------
SELECT
    decile,
    COUNT(*)                          AS county_count,
    ROUND(MIN(prevalence_pct), 2)     AS min_pct,
    ROUND(MAX(prevalence_pct), 2)     AS max_pct,
    ROUND(AVG(prevalence_pct), 2)     AS avg_pct
FROM (
    SELECT
        prevalence_pct,
        NTILE(10) OVER (ORDER BY prevalence_pct) AS decile
    FROM marts.fct_county_health_metrics
    WHERE measure_id   = 'OBESITY'    -- swap measure here
      AND has_acs_data = true
) sub
GROUP BY decile
ORDER BY decile;


-- -----------------------------------------------------------------------------
-- Q18: Cumulative population coverage — "how many people live in the hardest-hit
--      counties?"
--      Running total of population as we add counties from worst to best.
--      Answers: "The top 10% worst diabetes counties contain X% of the US population."
--      Useful for: impact sizing, resource allocation narrative
-- -----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        county_fips,
        county_name,
        state_abbr,
        prevalence_pct,
        total_population,
        national_pct_rank,
        SUM(total_population) OVER (
            ORDER BY prevalence_pct DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_population
    FROM marts.fct_county_health_metrics
    WHERE measure_id   = 'DIABETES'
      AND has_acs_data = true
),

totals AS (
    SELECT SUM(total_population) AS us_total_pop
    FROM marts.fct_county_health_metrics
    WHERE measure_id = 'DIABETES' AND has_acs_data = true
)

SELECT
    r.county_fips,
    r.county_name,
    r.state_abbr,
    r.prevalence_pct,
    r.total_population,
    r.cumulative_population,
    ROUND(
        r.cumulative_population::NUMERIC / t.us_total_pop * 100, 2
    ) AS cumulative_pop_pct_of_us
FROM ranked r
CROSS JOIN totals t
ORDER BY r.prevalence_pct DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- Q19: Unexpected high burden — wealthy counties with poor health outcomes
--      Finds counties in the top income quartile but high disease burden.
--      Challenges the simple "income → health" narrative.
--      Useful for: nuanced storytelling, anomaly detection
-- -----------------------------------------------------------------------------
SELECT
    county_fips,
    county_name,
    state_abbr,
    prevalence_pct,
    national_pct_rank,
    median_household_income,
    income_quartile,
    pct_uninsured,
    pct_65_plus,
    population_size_category
FROM marts.fct_county_health_metrics
WHERE measure_id       = 'DIABETES'
  AND income_quartile  = 4            -- highest income counties
  AND national_pct_rank >= 75         -- but still in worst 25% nationally
  AND has_acs_data     = true
ORDER BY prevalence_pct DESC;


-- -----------------------------------------------------------------------------
-- Q20: State-level rolling 3-county moving average of county prevalence
--      Counties ordered by prevalence within each state; moving average
--      smooths the ranking curve for cleaner trend visualization.
--      Useful for: within-state distribution line chart
-- -----------------------------------------------------------------------------
WITH county_ranked AS (
    SELECT
        county_fips,
        county_name,
        state_abbr,
        prevalence_pct,
        ROW_NUMBER() OVER (
            PARTITION BY state_abbr
            ORDER BY prevalence_pct DESC
        ) AS county_rank_in_state
    FROM marts.fct_county_health_metrics
    WHERE measure_id   = 'DIABETES'
      AND has_acs_data = true
      AND state_abbr  != 'US'
)

SELECT
    state_abbr,
    county_name,
    county_rank_in_state,
    prevalence_pct,
    ROUND(
        AVG(prevalence_pct) OVER (
            PARTITION BY state_abbr
            ORDER BY county_rank_in_state
            ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        )::NUMERIC, 2
    ) AS moving_avg_3_county
FROM county_ranked
WHERE state_abbr = 'TX'    -- swap state here
ORDER BY state_abbr, county_rank_in_state;
