select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term
from datalake_amplitude_clean_prod."170698_listing_page_viewed_events" damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
where year >= 2019 and platform = 'Web'
group by 2,3,4,5,6,7,8