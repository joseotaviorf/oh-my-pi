with
date_series as (
    select distinct
        date(week_start) as week_start,
        date(week_end) as week_end
    from datalake_clean.ods_dim_date dd
    where date(date) >= current_date - interval '180' day and date(week_start) < date_trunc('week', current_date)
        and date != ''
),
house_date_series as (
    select distinct
        h.id as id_house,
        dd.week_start,
        dd.week_end
    from datalake_ebdb_clean_prod.house h
    join datalake_ebdb_clean_prod.access_type at
        on at.id_house = h.id
    cross join date_series dd
    where h.dt_first_publication is not null
),
key_type_base as (
    with
    key_type_aud as (
        select
            id_house,
            id_type,
            rev,
            from_unixtime(cast(ure.ts_revision as bigint)/1000) as date,
            cast(date_trunc('week', from_unixtime(cast(ure.ts_revision as bigint)/1000)) as date) + interval '6' day as week_end
        from datalake_ebdb_clean_prod.access_type_aud aud
        left join datalake_ebdb_clean_prod.user_revision_entity ure
            on ure.id = aud.rev
        where aud.mod_type = true
    ),
    key_type_ordered as (
        select
            id_house,
            id_type,
            kt.name as key_type_history,
            week_end as week_end_key_type_start,
            coalesce(lead(week_end) over (partition by id_house order by date), date_trunc('week', current_date) + interval '6' day) as week_end_key_type_end,
            row_number() over (partition by id_house, week_end order by date desc) as order_key_type
        from key_type_aud
        left join datalake_ebdb_clean_prod.key_type kt
            on kt.id = key_type_aud.id_type
    )
     select
         id_house,
         key_type_history,
         dd.week_start,
         dd.week_end,
         week_end_key_type_start,
         week_end_key_type_end
     from key_type_ordered
     join date_series dd
         on dd.week_end >= week_end_key_type_start and dd.week_end < week_end_key_type_end
     where order_key_type = 1
 ),
key_location_base as (
    with
    key_location_aud as (
        select
            id_house,
            id_authorization,
            rev,
            from_unixtime(cast(ure.ts_revision as bigint)/1000) as date,
            cast(date_trunc('week', from_unixtime(cast(ure.ts_revision as bigint)/1000)) as date) + interval '6' day as week_end
        from datalake_ebdb_clean_prod.access_type_aud aud
        left join datalake_ebdb_clean_prod.user_revision_entity ure
            on ure.id = aud.rev
        where aud.mod_authorization = true
    ),
    key_location_ordered as (
        select
            id_house,
            id_authorization,
            at.name as key_location_history,
            week_end as week_end_key_location_start,
            coalesce(lead(week_end) over (partition by id_house order by date), date_trunc('week', current_date) + interval '6' day) as week_end_key_location_end,
            row_number() over (partition by id_house, week_end order by date desc) as order_key_location
        from key_location_aud
        left join datalake_ebdb_clean_prod.access_authorization_type at
            on at.id = key_location_aud.id_authorization
    )
    select
        id_house,
        key_location_history,
        dd.week_start,
        dd.week_end,
        week_end_key_location_start,
        week_end_key_location_end
    from key_location_ordered
    join date_series dd
        on dd.week_end >= week_end_key_location_start and dd.week_end < week_end_key_location_end
    where order_key_location = 1
),
who_is_living_base as (
    with
    who_is_living_aud as (
        select
            id_house,
            id_occupant,
            rev,
            from_unixtime(cast(ure.ts_revision as bigint)/1000) as date,
            cast(date_trunc('week', from_unixtime(cast(ure.ts_revision as bigint)/1000)) as date) + interval '6' day as week_end
        from datalake_ebdb_clean_prod.access_type_aud aud
        left join datalake_ebdb_clean_prod.user_revision_entity ure
            on ure.id = aud.rev
        where aud.mod_occupant = true
    ),
    who_is_living_ordered as (
        select
            id_house,
            id_occupant,
            ot.name as who_is_living_history,
            week_end as week_end_who_is_living_start,
            coalesce(lead(week_end) over (partition by id_house order by date), date_trunc('week', current_date) + interval '6' day) as week_end_who_is_living_end,
            row_number() over (partition by id_house, week_end order by date desc) as order_who_is_living
        from who_is_living_aud
        left join datalake_ebdb_clean_prod.occupant_type ot
            on ot.id = who_is_living_aud.id_occupant
    )
    select
        id_house,
        who_is_living_history,
        dd.week_start,
        dd.week_end,
        week_end_who_is_living_start,
        week_end_who_is_living_end
    from who_is_living_ordered
    join date_series dd
        on dd.week_end >= week_end_who_is_living_start and dd.week_end < week_end_who_is_living_end
    where order_who_is_living = 1
),
house_weekly_entrance as (
select
    CAST(hds.id_house AS VARCHAR) AS id_house,
    CAST(hds.week_start AS VARCHAR) AS week_start,
    CAST(hds.week_end AS VARCHAR) AS week_end,
    CAST(klb.key_location_history AS VARCHAR) AS key_location_history,
    CAST(ktb.key_type_history AS VARCHAR) AS key_type_history,
    CAST(wlb.who_is_living_history AS VARCHAR) AS who_is_living_history,
    CAST(NOW() AS VARCHAR) AS ts_load
from house_date_series hds
left join key_location_base klb
    on klb.id_house = hds.id_house and hds.week_end = klb.week_end
left join key_type_base ktb
    on ktb.id_house = hds.id_house and ktb.week_end = hds.week_end
left join who_is_living_base wlb
    on wlb.id_house = hds.id_house and hds.week_end = wlb.week_end
where klb.id_house is not null
order by 3,2
)
select * from house_weekly_entrance