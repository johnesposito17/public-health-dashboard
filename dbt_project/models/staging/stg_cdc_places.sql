/*
  stg_cdc_places
  ──────────────
  Cleans and standardizes the raw CDC PLACES county-level data.

  Key transformations:
    - Renames columns to consistent snake_case
    - Casts year, population, and prevalence fields to correct numeric types
    - Ensures county_fips is zero-padded to 5 characters
    - Deduplicates to the most recent year per county × measure using
      row_number(), so downstream models get one row per county-measure
      without needing to filter on year themselves
    - Drops Socrata metadata columns not needed downstream
*/

with source as (

    select * from {{ source('raw', 'cdc_places_county') }}

),

renamed as (

    select
        -- geography
        lpad(cast(locationid as text), 5, '0')  as county_fips,
        locationname                             as county_name,
        stateabbr                                as state_abbr,
        statedesc                                as state_name,

        -- measure identifiers
        cast(year as integer)                    as data_year,
        category                                 as measure_category,
        categoryid                               as category_id,
        measure                                  as measure_name,
        measureid                                as measure_id,
        short_question_text                      as measure_short,
        datasource                               as data_source,

        -- prevalence values
        cast(data_value as numeric(6, 2))           as prevalence_pct,
        cast(low_confidence_limit as numeric(6, 2)) as ci_low,
        cast(high_confidence_limit as numeric(6, 2)) as ci_high,
        data_value_unit                              as value_unit,
        datavaluetypeid                              as value_type_id,

        -- population denominators
        cast(totalpopulation as integer)         as total_population,
        cast(totalpop18plus as integer)          as population_18_plus

    from source
    -- Exclude the single CDC aggregate row (state_abbr = 'US', fips = '00059')
    where locationid != '00059'

),

deduped as (

    /*
      PLACES 2025 release contains both 2022 and 2023 survey years for most
      measures. We keep only the most recent year per county × measure so
      downstream joins produce exactly one row per combination.
    */
    select
        *,
        row_number() over (
            partition by county_fips, measure_id
            order by data_year desc
        ) as _row_num

    from renamed

)

select
    county_fips,
    county_name,
    state_abbr,
    state_name,
    data_year,
    measure_category,
    category_id,
    measure_name,
    measure_id,
    measure_short,
    data_source,
    prevalence_pct,
    ci_low,
    ci_high,
    value_unit,
    value_type_id,
    total_population,
    population_18_plus

from deduped
where _row_num = 1
