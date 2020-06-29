select
    ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
    json_extract_scalar(event_properties, '$.visit_code') as visit_code,
    json_extract_scalar(event_properties, '$.house_id') as house_id
from datalake_amplitude_clean_prod.events damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
where year >= 2020
    and platform = 'Web'
    and id_app = 170698
    and event_type = 'offer_submitted'
group by 1,2,3,4,5,6,7,8,9,10
