/*
  fct_county_health_metrics
  ──────────────────────────
  Fact table of county-level chronic disease prevalence estimates enriched
  with demographic context and ranking metrics.

  Grain: one row per county × health measure.
  ~125,000 rows (3,140 counties × 40 measures).

  Ranking fields:
    national_pct_rank  — PERCENT_RANK within each measure across all US counties.
                         0 = lowest prevalence, 100 = highest. Useful for "how
                         does this county compare nationally for diabetes?"
    state_pct_rank     — same, but ranked only within the county's state.
                         Useful for within-state comparisons on a dashboard.

  Quartile fields (from dim_county_demographics, county-grain):
    income_quartile    — 1 = lowest-income counties, 4 = highest-income
    uninsured_quartile — 1 = lowest uninsured rate, 4 = highest
    poverty_quartile   — 1 = lowest poverty rate, 4 = highest
*/

with base as (

    select * from {{ ref('int_county_health_demographics') }}

),

dim as (

    select
        county_fips,
        income_quartile,
        uninsured_quartile,
        poverty_quartile,
        population_quartile,
        population_size_category
    from {{ ref('dim_county_demographics') }}

),

with_ranks as (

    select
        b.*,

        -- National percentile rank within each measure (0–100)
        round(
            cast(
                percent_rank() over (
                    partition by b.measure_id
                    order by b.prevalence_pct asc nulls last
                ) * 100
            as numeric),
            1
        ) as national_pct_rank,

        -- State-level percentile rank within each state × measure
        round(
            cast(
                percent_rank() over (
                    partition by b.state_abbr, b.measure_id
                    order by b.prevalence_pct asc nulls last
                ) * 100
            as numeric),
            1
        ) as state_pct_rank

    from base b

)

select
    -- ── Keys ───────────────────────────────────────────────────────────────
    r.county_fips,
    r.measure_id,

    -- ── Geography ──────────────────────────────────────────────────────────
    r.county_name,
    r.state_abbr,
    r.state_name,

    -- ── Measure metadata ───────────────────────────────────────────────────
    r.data_year,
    r.measure_category,
    r.measure_name,
    r.measure_short,

    -- ── Prevalence ─────────────────────────────────────────────────────────
    r.prevalence_pct,
    r.ci_low,
    r.ci_high,

    -- ── Population context ─────────────────────────────────────────────────
    r.total_population,
    r.population_18_plus,

    -- ── Demographic context (for correlation analysis) ──────────────────────
    r.median_household_income,
    r.pct_uninsured,
    r.pct_below_poverty,
    r.pct_65_plus,
    r.median_age,
    r.pct_white,
    r.pct_black,
    r.pct_asian,
    r.pct_hispanic,

    -- ── Rankings ───────────────────────────────────────────────────────────
    r.national_pct_rank,
    r.state_pct_rank,

    -- ── Quartile segments (from dim) ───────────────────────────────────────
    d.income_quartile,
    d.uninsured_quartile,
    d.poverty_quartile,
    d.population_quartile,
    d.population_size_category,

    -- ── Data quality flag ──────────────────────────────────────────────────
    r.has_acs_data

from with_ranks r
left join dim d on r.county_fips = d.county_fips
