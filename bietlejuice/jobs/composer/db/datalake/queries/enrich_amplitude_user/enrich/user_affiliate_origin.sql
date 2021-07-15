with amplitude_affiliate_tracking as(
	with amplitude_events as (
    SELECT DISTINCT
        id_user,
        get_json_object(user_properties, '$.utm_source') as utm_source,
        get_json_object(user_properties, '$.utm_medium') as utm_medium,
        get_json_object(user_properties, '$.utm_campaign') as utm_campaign,
        lower(regexp_replace(get_json_object(user_properties, '$.utm_campaign'), '[^\\w]+|_', '')) as utm_campaign_cleaned,
        get_json_object(user_properties, '$.utm_content') as utm_content,
        get_json_object(user_properties, '$.utm_term') as utm_term,
        get_json_object(user_properties, '$.platform') as platform,
        device_type as device_type,
        country as country,
        region as region,
        city as city,
        ts_client_event,
        ts_event
    FROM datalake_amplitude_clean.events
    WHERE event_type IN ('signup_user_created', 'login_confirmation_viewed', 'home_page_viewed')
        AND id_app = 205027
        AND id_user is not null
    )
    select
      *,
      rank() over (partition by id_user order by ts_event, ts_client_event) as event_order
    from amplitude_events
)
select
	id_user,
	utm_source,
	utm_medium,
	utm_campaign,
	-- TODO [ODS]: we have a bug in this rule. I.g: Cases like 'sitelinkspoa' are considered like RMSP
	case
        when utm_campaign_cleaned like '%riodejaneiro%' or utm_campaign_cleaned like '%rj%' then 'Rio de Janeiro'
        when utm_campaign_cleaned like '%belohorizonte%' THEN 'Belo Horizonte'
        when utm_campaign_cleaned like '%florian_polis%' THEN 'Florianópolis'
        when utm_campaign_cleaned like '%bras_lia%' THEN 'Brasília'
        when utm_campaign_cleaned like '%goi_nia%' THEN 'Goiânia'
        when utm_campaign_cleaned like '%portoalegre%' or utm_campaign_cleaned like 'rs%' then 'Porto Alegre'
        when utm_campaign_cleaned like '%curitiba%' then 'Curitiba'
        when utm_campaign_cleaned like '%campinas%' then 'Campinas'
        when utm_campaign_cleaned like '%s_opaulo%' then 'RMSP'
        when utm_campaign_cleaned like '%sp%' then 'RMSP'
    end as city_campaign,
	utm_content,
	utm_term,
	platform,
	device_type,
	country,
	region,
	city,
	ts_client_event
from
	amplitude_affiliate_tracking
where event_order = 1