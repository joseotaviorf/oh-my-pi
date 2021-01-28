with all_apps_events(
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
        dt_event
    from datalake_amplitude_clean.170698_offer_submitted_events
    union all
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
        dt_event
    from datalake_amplitude_clean.170135_offer_submitted_events
    union all
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
        dt_event
    from datalake_amplitude_clean.183049_offer_submitted_events
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
from all_apps_events

