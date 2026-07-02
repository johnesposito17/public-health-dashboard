/*
  stg_acs_demographics
  ─────────────────────
  Cleans and standardizes the raw ACS 5-Year county demographic data.

  Key transformations:
    - Renames Census variable names to human-readable column names
    - Ensures county_fips is zero-padded to 5 characters
    - Parses county_name and state_name from the combined NAME field
    - Casts all numeric columns; nulls remain null (not coerced to 0)
    - Drops intermediate count columns used only to derive pct_* fields
*/

with source as (

    select * from {{ source('raw', 'acs_county_2022') }}

),

cleaned as (

    select
        -- geography
        lpad(cast(fips as text), 5, '0')            as county_fips,
        split_part("NAME", ', ', 1)                 as county_name,
        split_part("NAME", ', ', 2)                 as state_name,
        cast(state as text)                         as state_fips,
        cast(county as text)                        as county_fips_3,
        2022                                        as acs_year,

        -- population
        cast(total_population as integer)           as total_population,
        cast(median_age as numeric(5, 1))           as median_age,

        -- income & poverty
        cast(median_household_income as integer)    as median_household_income,
        cast(pct_below_poverty as numeric(5, 2))    as pct_below_poverty,

        -- health insurance
        cast(pct_uninsured as numeric(5, 2))        as pct_uninsured,

        -- age structure
        cast(pop_65_plus as integer)                as pop_65_plus,
        cast(pct_65_plus as numeric(5, 2))          as pct_65_plus,

        -- race / ethnicity (percentages derived in ingestion script)
        cast(pct_white as numeric(5, 2))            as pct_white,
        cast(pct_black as numeric(5, 2))            as pct_black,
        cast(pct_asian as numeric(5, 2))            as pct_asian,
        cast(pct_hispanic as numeric(5, 2))         as pct_hispanic,

        -- raw race counts (kept for flexibility in custom aggregations)
        cast(pop_white_alone as integer)            as pop_white_alone,
        cast(pop_black_alone as integer)            as pop_black_alone,
        cast(pop_asian_alone as integer)            as pop_asian_alone,
        cast(pop_hispanic_latino as integer)        as pop_hispanic_latino

    from source

)

select * from cleaned
