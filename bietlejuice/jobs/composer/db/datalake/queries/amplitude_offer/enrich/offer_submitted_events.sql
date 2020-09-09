with extracted_utms as (
    select
        id_user,
        id_app,
        cast(trim(get_json_object(event_properties, '$.house_id')) as string) as id_house,
        cast(trim(get_json_object(event_properties, '$.offer_id')) as string) as id_firestore,
        cast(get_json_object(user_properties , '$.platform') as string) as app_type,
        cast(get_json_object(user_properties, '$.utm_source') as string) as utm_source,
        cast(get_json_object(user_properties, '$.utm_medium') as string) as utm_medium,
        cast(get_json_object(user_properties, '$.utm_campaign') as string) as utm_campaign,
        cast(get_json_object(user_properties, '$.utm_content') as string) as utm_content,
        cast(get_json_object(user_properties, '$.utm_term') as string) as utm_term,
        date(ts_event) as dt_event,
        ts_event
    from
        datalake_amplitude_clean.events
    where
        event_type = 'offer_submitted'
        and id_app in (170698, 170135, 183049)
)
select
    id_user,
    id_app,
    id_house,
    id_firestore,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    case
        when (upper(utm_campaign) like '%BRANDED%' or upper(utm_campaign) like '%INSTITUCIONAL%') and
            lower(utm_campaign) not like '%non-branded%'
            then 'Branded'
        else 'Outro'
    end as branded,
    coalesce(
        (
            (upper(utm_campaign) like '%BRANDED%' or upper(utm_campaign) like '%INSTITUCIONAL%')
            and lower(utm_campaign) not like '%non-branded%'
        ), false
    ) as is_branded,
    dt_event
from extracted_utms

