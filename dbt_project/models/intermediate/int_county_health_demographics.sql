/*
  int_county_health_demographics
  ───────────────────────────────
  Joins PLACES health measures with ACS county demographics on county_fips.

  This is the single enriched dataset that feeds both mart tables. Keeping
  the join logic here (rather than duplicating it in each mart) means any
  future change to join keys or coalesce logic only needs to happen once.

  Grain: one row per county × health measure (same as stg_cdc_places).
  Left join preserves all PLACES counties even where ACS data is absent
  (e.g. Puerto Rico municipalities). The has_acs_data flag lets downstream
  models filter or handle those rows explicitly.
*/

with places as (

    select * from {{ ref('stg_cdc_places') }}

),

demographics as (

    select * from {{ ref('stg_acs_demographics') }}

),

joined as (

    select
        -- ── Geography ──────────────────────────────────────────────────────
        p.county_fips,
        p.county_name,
        p.state_abbr,
        p.state_name,

        -- ── Health measure ─────────────────────────────────────────────────
        p.data_year,
        p.measure_category,
        p.category_id,
        p.measure_name,
        p.measure_id,
        p.measure_short,

        -- ── Prevalence estimate ────────────────────────────────────────────
        p.prevalence_pct,
        p.ci_low,
        p.ci_high,
        p.total_population,
        p.population_18_plus,

        -- ── ACS demographics (null for counties without ACS match) ─────────
        d.median_age,
        d.median_household_income,
        d.pct_uninsured,
        d.pct_65_plus,
        d.pct_below_poverty,
        d.pct_white,
        d.pct_black,
        d.pct_asian,
        d.pct_hispanic,
        d.pop_white_alone,
        d.pop_black_alone,
        d.pop_asian_alone,
        d.pop_hispanic_latino,

        -- ── Join quality flag ──────────────────────────────────────────────
        case
            when d.county_fips is not null then true
            else false
        end as has_acs_data

    from places  p
    left join demographics d on p.county_fips = d.county_fips

)

select * from joined
