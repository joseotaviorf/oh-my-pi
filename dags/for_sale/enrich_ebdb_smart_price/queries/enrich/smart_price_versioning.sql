WITH
status_version_order AS (
    SELECT
      svo.id_house,
      svo.rev,
      svo.days_in_status,
      svo.status,
      svo.status_reason,
      svo.listing_version,
      LEAD(svo.listing_version) OVER(PARTITION BY svo.id_house ORDER BY svo.ts_state_started, svo.ts_state_ended) AS nxt_version,
      MIN(svo.ts_state_started) OVER(PARTITION BY svo.id_house, svo.listing_version) AS ts_status_started,
      MAX(svo.ts_state_started) OVER(PARTITION BY svo.id_house, svo.listing_version) AS ts_status_ended,
      svo.state_order,
      svo.max_state_order
    FROM
      datalake_ebdb_listing.lbc_status_version_order AS svo
),
house_status_version_last_status AS (
    SELECT
      svo.id_house,
      svo.rev,
      svo.days_in_status,
      svo.status,
      svo.status_reason,
      svo.listing_version,
      svo.nxt_version,
      svo.ts_status_started,
      svo.ts_status_ended,
      svo.state_order,
      FIRST(svo.status) OVER(PARTITION BY svo.id_house ORDER BY svo.state_order DESC) AS last_status,
      svo.max_state_order
    FROM
      status_version_order AS svo
    WHERE
      svo.nxt_version IS NULL
      OR svo.nxt_version = svo.listing_version + 1
),
house_listing_full AS (
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
    select
        cast(cast(id_house as string)||'00'||cast(listing_version as string) as bigint) as id_house_listing,
        id_house,
        listing_version,
        status,
        ts_status_started AS ts_listing_version_start,
        ts_status_ended AS ts_listing_version_end
    from 
      house_status_version_last_status
),
smp_aud as (
    select
        dpa.id_house,
        dpa.id,
        dpa.rev,
        dpa.id_dynamic_pricing_parameter,
        dpa.status,
        cast(from_unixtime(cast(ure.ts_revision as bigint)/1000) as timestamp) as date_time,
        -- TODO: Remove fixed_mod_status column after bugs in the table dynamic_pricing_house_aud are fixed
        coalesce(lag(status) over (partition by id_house order by dpa.rev), '') != status as fixed_mod_status
    from
        datalake_ebdb_clean.dynamic_pricing_house_aud  dpa
    join
        datalake_ebdb_clean.user_revision_entity ure
            on ure.id = dpa.rev
            and mod_status = true
),
house_smp_status as (
    select
        hlf.id_house_listing,
        smp.id_house,
        smp.id as id_dynamic_pricing,
        smp.rev as rev_dynamic_pricing_house_aud,
        smp.id_dynamic_pricing_parameter,
        smp.status,
        smp.date_time as ts_start_status,
        coalesce(lead(smp.date_time) over(partition by smp.id_house order by smp.rev), cast(current_date as timestamp))  as ts_end_status
    from
        smp_aud smp
    join
        house_listing_full hlf
            on hlf.id_house = smp.id_house
            and smp.date_time between coalesce(hlf.ts_listing_version_start, cast('1900-01-01' as timestamp)) and coalesce(hlf.ts_listing_version_end, now())
            and smp.date_time is not null
            -- TODO: Remove fixed_mod_status column after bugs in the table dynamic_pricing_house_aud are fixed
            and fixed_mod_status = true
),
base as (
    select
        id_house_listing,
        id_house,
        id_dynamic_pricing,
        rev_dynamic_pricing_house_aud,
        id_dynamic_pricing_parameter,
        status,
        lag(status) over (partition by id_house_listing order by ts_start_status) previous_status,
        ts_start_status,
        ts_end_status
    from
        house_smp_status
    where
        ts_end_status > ts_start_status
),
version_status as (
    select
        id_house_listing,
        id_house,
        id_dynamic_pricing,
        rev_dynamic_pricing_house_aud,
        id_dynamic_pricing_parameter,
        status,
        previous_status,
        ts_start_status,
        ts_end_status,
        case when status = 'ACTIVE' and coalesce(previous_status,'abracadabra') != 'PAUSED' then dense_rank() over (partition by id_house_listing, status order by ts_start_status) end as version_inactive
    from
        base
),
version_for_all as (
    select
        id_house_listing,
        id_house,
        id_dynamic_pricing,
        rev_dynamic_pricing_house_aud,
        id_dynamic_pricing_parameter,
        status,
        previous_status,
        ts_start_status,
        ts_end_status,
        max(version_inactive) over (partition by id_house_listing order by ts_start_status rows unbounded preceding) version
    from
        version_status
)
select
    cast(cast(id_house_listing as string)||'00'||cast(coalesce(version,0) as string) as bigint) as id_smart_price,
    id_house_listing,
    id_house,
    id_dynamic_pricing,
    rev_dynamic_pricing_house_aud,
    id_dynamic_pricing_parameter,
    status,
    ts_start_status,
    ts_end_status
from
    version_for_all