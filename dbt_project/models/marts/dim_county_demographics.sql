/*
  dim_county_demographics
  ────────────────────────
  County-level demographic and socioeconomic dimension table.
  One row per county. Joins to fct_county_health_metrics on county_fips.

  Adds NTILE-based quartile and population tier classifications so
  dashboard consumers and SQL analysts don't need to re-derive them.

  Quartile convention (all fields):
    1 = lowest (e.g. lowest income, least uninsured, smallest population)
    4 = highest
*/

with base as (

    select * from {{ ref('stg_acs_demographics') }}

),

with_tiers as (

    select
        -- ── Geography ──────────────────────────────────────────────────────
        county_fips,
        county_name,
        state_name,
        state_fips,
        acs_year,

        -- ── Population ─────────────────────────────────────────────────────
        total_population,
        median_age,


        -- ── Income & poverty ───────────────────────────────────────────────
        median_household_income,
        pct_below_poverty,

        -- ── Health coverage ────────────────────────────────────────────────
        pct_uninsured,

        -- ── Age structure ──────────────────────────────────────────────────
        pop_65_plus,
        pct_65_plus,

        -- ── Race / ethnicity ───────────────────────────────────────────────
        pct_white,
        pct_black,
        pct_asian,
        pct_hispanic,
        pop_white_alone,
        pop_black_alone,
        pop_asian_alone,
        pop_hispanic_latino,

        -- ── Quartile classifications ───────────────────────────────────────
        ntile(4) over (
            order by median_household_income asc nulls last
        ) as income_quartile,

        ntile(4) over (
            order by pct_uninsured asc nulls last
        ) as uninsured_quartile,

        ntile(4) over (
            order by pct_below_poverty asc nulls last
        ) as poverty_quartile,

        ntile(4) over (
            order by total_population asc
        ) as population_quartile,

        -- ── Population size category (for dashboard filters) ───────────────
        case
            when total_population <  25000  then 'Rural (<25k)'
            when total_population <  100000 then 'Small (25k–100k)'
            when total_population <  500000 then 'Mid-size (100k–500k)'
            when total_population < 1000000 then 'Large (500k–1M)'
            else                                 'Metro (1M+)'
        end as population_size_category

    from base

)

select * from with_tiers
