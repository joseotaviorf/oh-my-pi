with house_aud as (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made                                                   --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    select
        from_unixtime(cast(rev.ts_revision as bigint)/1000) as revision_time, -- datetime status started
        cast(from_unixtime(cast(rev.ts_revision as bigint)/1000) as date) as status_date, -- date status started
        rev.id_user usuario_id, -- user responsible to change status
        rev.reason as motivo, -- reason status changed
        lag(i.status) over(partition by i.id_house order by i.rev) as previous_status, -- previous status ordered by the datetime that happened
        lag(i.rent) over(partition by i.id_house order by i.rev) as previous_rent_price,
        i.status,
        i.rent as aluguel,
        i.id_house,
        i.rev,
        i.mod_status,
        i.dt_first_publication
    from datalake_ebdb_clean.house_aud i
    inner join datalake_ebdb_clean.user_revision_entity rev
        on rev.id = i.rev
),
house_status_history as (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
    select
        id_house,
        rev,
        mod_status,
        max(dt_first_publication) over(partition by id_house) as ts_first_publication,
        revision_time as ts_status_changed,
        status as status_history,
        lead(revision_time) over(partition by id_house order by rev) as next_status_change_time,
        row_number() over(partition by id_house order by rev) as order_status
    from house_aud
    where (status <> previous_status or previous_status is null)
),
house_new_status_new_date as (
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                                                                                             --
-- We will use this column to check if a new version will be created to this house (a new version will be created when the house is unpublished for 12 weeks or more)  --
-- Since we will count from the day it turns 12 weeks, there's no need to extract 1 day from the end_date in date_diff                                                 --
-- Since we are using date_diff, we are considering the whole part of the number, so if the difference is 83.7, it won't consider as recovered                         --
-- For the older houses there are cases of status_history blank, so we have to input status_history = 'publicado' (this happens to status from 2015)                   --
-- In these cases of status_history_blank we also update the status changed date to the first_publication_date                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    select
        *,
        case when status_history = 'despublicado' then datediff(cast(coalesce(next_status_change_time,now()) as date), cast(ts_status_changed as date)) end as days_unpublished,
        case when status_history is null then 'publicado' else status_history end as new_status_history,
        case when status_history is null then ts_first_publication else ts_status_changed end as new_ts_status_changed,
        max(order_status) over(partition by id_house) as max_order_status
    from house_status_history
),
house_status_version_changes as (
--------------------------------------------------------------------------------------------------------
-- Create column to identify moments where house changed status would create a new version/listing    --
-- The moments are: when there is a status rented or a status unpublished with days_unpublished >= 84 --
-- With a cumulative sum we can identify when a new change of status happens                          --
--------------------------------------------------------------------------------------------------------
    select
        *,
        case when new_status_history = 'alugado' or
                  (new_status_history = 'despublicado' and days_unpublished >= 84) then 1
             else 0 end as events_change_version,
        case when new_status_history = 'alugado' or
                  (new_status_history = 'despublicado' and days_unpublished >= 84) then new_status_history
             end as events_change_status,
        sum(case when new_status_history = 'alugado' or
                      (new_status_history = 'despublicado' and days_unpublished >= 84) then 1
                 else 0 end) over (partition by id_house order by rev rows unbounded preceding) as sum_events_change_version
    from house_new_status_new_date h_new
),
house_status_version_first_publi as (
------------------------------------------------------------------------------------------------------------------------------------
-- Although a rented status is a trigger to a new version, the new version will only starts when there is a new published status  --
-- The rented status will still be a part of previous status and the new published status will be the start of the new version    --
------------------------------------------------------------------------------------------------------------------------------------
    select
        *,
        min(case when new_status_history = 'publicado' then new_ts_status_changed
                 end) over(partition by id_house, sum_events_change_version order by rev) as first_publication_change_version
    from house_status_version_changes
),
house_status_version_publications as (
------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- The rented status will still be a part of previous status, and so will be all status different from published after rental                                   --
-- All versions begin with a date from published status, without a published status there will not be a version_start_date                                      --
------------------------------------------------------------------------------------------------------------------------------------------------------------------
    select
        *,
        max(first_publication_change_version) over (partition by id_house order by rev rows unbounded preceding) as publication_version_date
    from house_status_version_first_publi
),
house_status_version_order_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                                    --
--------------------------------------------------------------------------------------------------------
    select
        *,
        0 as order_version
    from house_status_version_publications
    where publication_version_date is null
),
house_status_version_order_not_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on non null publication dates                                                    --
--------------------------------------------------------------------------------------------------------
    select
        *,
        dense_rank() over(partition by id_house order by publication_version_date) as order_version
    from house_status_version_publications
    where publication_version_date is not null
),
house_status_version_order as (
--------------------------------------------------------------------------------------------------------
-- Define order version as union all both above                                                   --
--------------------------------------------------------------------------------------------------------
    select * from house_status_version_order_null_publi_date
    union all
    select * from house_status_version_order_not_null_publi_date
),
max_status_order as (
--------------------------------------------------------------------------------------------------------
-- Identify the last status to each version                                                           --
--------------------------------------------------------------------------------------------------------
--     with

    select
        id_house,
        order_version,
        max(order_status) as max_order_status
    from house_status_version_order
    group by id_house, order_version
),
house_status_version_last_status as (
    select
       hs_vo.*,
       max(
         case
           when hs_vo.new_status_history = 'despublicado'
             then new_ts_status_changed
         end
       ) over(partition by hs_vo.id_house, hs_vo.order_version) as ts_last_de_publication,
       case when ms_o.max_order_status is not null then hs_vo.new_status_history end as last_status,
       max(hs_vo.order_status) over(partition by hs_vo.id_house, hs_vo.order_version) as max_order_status_version
    from house_status_version_order hs_vo
    left join max_status_order ms_o
        on hs_vo.id_house = ms_o.id_house
        and hs_vo.order_version = ms_o.order_version
        and hs_vo.order_status = ms_o.max_order_status
),
house_listing_plain as (
--------------------------------------------------------------------------------------------------------
-- Create listings column according to version                                                        --
-- Create column to identify category (using column from join with status_change_version              --
-- Keep only the version changes                                                                      --
--------------------------------------------------------------------------------------------------------
    select
        hs_v.id_house,
        hs_v.order_version as version,
        max(status_history) as status_history,
        max(ts_status_changed) as ts_status_changed,
        max(hs_v.last_status) as status,
        min(cast(hs_v.publication_version_date as timestamp)) as ts_listing_version_start,
        max(coalesce(hs_v.next_status_change_time,cast('2200-01-01 12:00:00' as timestamp))) as ts_listing_version_end
    from  house_status_version_last_status hs_v
    group by 1, 2
),
house_listing_full as (
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
    select
        cast(cast(id_house as string)||'00'||cast(version as string) as bigint) as id_house_listing,
        id_house,
        version,
        status,
        status_history,
        ts_status_changed,
        ts_listing_version_start,
        nullif(cast(ts_listing_version_end as timestamp),cast('2200-01-01 12:00:00' as timestamp)) as ts_listing_version_end
    from house_listing_plain
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
