select
    coalesce(merged_amplitude_id, id_amplitude) as id_amplitude,
    id_session,
    ep_house_id as id_house,
    up_utm_source as utm_source,
    up_utm_medium as utm_medium,
    up_utm_campaign as utm_campaign,
    up_utm_content as utm_content,
    up_utm_term as utm_term,
    min(ts_event) as ts_event
from datalake_amplitude_clean.`170698_home_page_viewed_events` damcs
left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
where date(cast(year as string) || '-' || cast(month as string) || '-' || cast(day as string)) >= current_date - interval '9' month
    and platform = 'Web'
group by 1,2,3,4,5,6,7,8
