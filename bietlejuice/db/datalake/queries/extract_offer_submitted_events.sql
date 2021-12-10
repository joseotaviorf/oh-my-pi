select
    date(ts_event) as dt_event,
    ts_event,
    cast(id_app as integer) as id_app,
    cast(json_extract_scalar(user_properties , '$.platform') as varchar) as app_type,
    ev.id_user as id_user,
    cast(trim(json_extract_scalar(event_properties, '$.house_id')) as varchar) as id_house,
    CAST(TRIM(COALESCE(
        JSON_EXTRACT_SCALAR(event_properties, '$.offer_id'),
        REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(event_properties, '$.uri'),'(?<=\/offer|aluguel\/).*?(?=\/)', 0)
    )) AS VARCHAR) AS id_firestore,
    cast(json_extract_scalar(user_properties, '$.utm_source') as varchar) as utm_source,
    cast(json_extract_scalar(user_properties, '$.utm_medium') as varchar) as utm_medium,
    cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar) as utm_campaign,
    cast(json_extract_scalar(user_properties, '$.utm_content') as varchar) as utm_content,
    cast(json_extract_scalar(user_properties, '$.utm_term') as varchar) as utm_term,
    case
        when (UPPER(cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar)) like '%BRANDED%'
            or UPPER(cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar)) like '%INSTITUCIONAL%')
            and lower(cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar)) NOT like '%non-branded%'
            then 'Branded'
        else 'Outro'
    end as branded
from
    datalake_amplitude_clean_prod.events ev
where
    event_type in ('offer_submitted')
    and id_app in (170698, 170135, 183049)