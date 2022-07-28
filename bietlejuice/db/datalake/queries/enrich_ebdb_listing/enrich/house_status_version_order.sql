with house_aud as (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made                                                --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    select
        cast(from_unixtime(cast(rev.ts_revision as bigint)/1000) as timestamp)  as revision_time,
        cast(from_unixtime(cast(rev.ts_revision as bigint)/1000) as date) as status_date,
        rev.id_user,
        rev.reason,
        lag(h_aud.status) over(partition by h_aud.id_house order by h_aud.rev) as previous_status,
        lag(h_aud.rent) over(partition by h_aud.id_house order by h_aud.rev) as previous_rent_price,
        h_aud.status,
        h.id_region,
        h_aud.rent,
        h_aud.id_house,
        h_aud.rev,
        h_aud.mod_rent,
        h_aud.dt_first_publication
    from datalake_ebdb_clean.house_aud h_aud
    join datalake_ebdb_clean.house h
        on h.id = h_aud.id_house
    inner join datalake_ebdb_clean.user_revision_entity rev
        on rev.id = h_aud.rev
),
house_status_history as (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
    select
        id_house,
        id_region,
        rev,
        max(dt_first_publication) over(partition by id_house) as ts_first_publication,
        revision_time as ts_status_changed,
        status as status_history,
        reason,
        lead(revision_time) over(partition by id_house order by rev) as ts_status_changed_next,
        row_number() over(partition by id_house order by rev) as order_status
    from house_aud
    where (status <> previous_status or previous_status is null)
),
house_new_status_new_date as (
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                                                                                           --
-- We will use this column to check if a new version will be created to this house (a new version will be created when the house is unpublished for 12 weeks or more)  --
-- Since we will count from the day it turns 12 weeks, there's no need to extract 1 day from the end_date in date_diff                                                 --
-- Since we are using date_diff, we are considering the whole part of the number, so if the difference is 83.7, it won't consider as recovered                         --
-- For the older houses there are cases of status_history blank, so we have to input status_history = 'publicado' (this happens to status from 2015)                   --
-- In these cases of status_history_blank we also update the status changed date to the first_publication_date                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    select
        *,
        case
            when status_history = 'despublicado'
            -- SparkSQL's datediff ignores the time part, so we get the seconds diff and convert it to integer days.
            -- 60s*60m*24h = 86400s
            then CAST((CAST(CAST(coalesce(ts_status_changed_next, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(ts_status_changed AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        end as days_unpublished,
        case when status_history is null then 'publicado' else status_history end as status_history_new,
        case when status_history is null then ts_first_publication else ts_status_changed end as ts_status_changed_new,
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
        case when status_history_new = 'alugado' or
                  (status_history_new = 'despublicado' and days_unpublished >= 84) then 1
             else 0 end as events_change_version,
        case when status_history_new = 'alugado' or
                  (status_history_new = 'despublicado' and days_unpublished >= 84) then status_history_new
             end as events_change_status,
        sum(case when status_history_new = 'alugado' or
                      (status_history_new = 'despublicado' and days_unpublished >= 84) then 1
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
        min(case when status_history_new = 'publicado' then ts_status_changed_new
                 end) over(partition by id_house, sum_events_change_version order by rev) as first_publication_change_version
    from house_status_version_changes
),
house_status_version_publications as (
------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- The rented status will still be a part of previous status, and so will be all status different from published after rental                                   --
-- All versions begin with a date from published status, without a published status there will not be a version_start_date                                      --
------------------------------------------------------------------------------------------------------------------------------------------------------------------
    select
        id_house,
        id_region,
        rev,
        reason,
        status_history,
        status_history_new,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_new,
        ts_status_changed_next,
        order_status,
        max_order_status,
        events_change_status,
        max(first_publication_change_version) over (partition by id_house order by rev rows unbounded preceding) as publication_version_date
    from house_status_version_first_publi
),
house_status_version_order_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                               --
--------------------------------------------------------------------------------------------------------
    select
        *,
        0 as order_version
    from house_status_version_publications
    where publication_version_date is null
),
house_status_version_order_not_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on non null publication dates                                           --
--------------------------------------------------------------------------------------------------------
    select
        *,
        dense_rank() over(partition by id_house order by publication_version_date) as order_version
    from house_status_version_publications
    where publication_version_date is not null
)
select * from house_status_version_order_null_publi_date
union all
select * from house_status_version_order_not_null_publi_date
