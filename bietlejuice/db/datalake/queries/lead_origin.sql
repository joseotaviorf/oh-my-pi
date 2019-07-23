with t_all as (
    with prep_1 as (
    select  cast(regexp_extract(e_lead_id, '(^\d+)') as bigint) as id_lead,
            null as firestore_id,
            null as e_formfield_lead_uuid,
            1 as rule_num,
            'referral' as rule,
            event_time,
            u_initial_utm_campaign,
            u_initial_utm_medium,
            u_initial_utm_source,
            u_initial_utm_content,
            u_initial_utm_term,
            u_platform,
            region,
            city,
            uuid
    from datalake_clean.amplitude_events ae
        where et in
            ('referral_confirmation_page_viewed',
            'referral_opportunity_confirmed',
            'referral_listing_confirmed',
            'referral_form_response_received')
            and	ym >= '2018-05'
            and ae.app = '205027'
            and regexp_like(e_lead_id, '(^\d+)')
    -- enriching with amplitude from SPARK processing
    union
        select
            cast(regexp_extract(
                coalesce(cast(json_extract(event_properties, '$.lead_id') as varchar), '')
                , '(^\d+)') as bigint) as id_lead,
            null as firestore_id,
            null as e_formfield_lead_uuid,
            1 as rule_num,
            'referral' as rule,
            event_time,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
            coalesce(region, '') as region,
            coalesce(city, '') as city,
            coalesce(uuid, '') as uuid
    from datalake_clean_spark.amplitude_events
        where event_type in
            ('referral_confirmation_page_viewed',
            'referral_opportunity_confirmed',
            'referral_listing_confirmed',
            'referral_form_response_received')
            and	year >= 2019
            and app = 205027
            and regexp_like(cast(json_extract(event_properties, '$.lead_id') as varchar), '(^\d+)')
    ),
    prep_2 as (
        select 	cast(regexp_extract(e__lead_id, '(^\d+)') as bigint) as id_lead,
            null as firestore_id,
            null as e_formfield_lead_uuid,
            2 as rule_num,
            'referral_2' as rule,
            event_time,
            u_initial_utm_campaign,
            u_initial_utm_medium,
            u_initial_utm_source,
            u_initial_utm_content,
            u_initial_utm_term,
            u_platform,
            region,
            city,
            uuid
    from datalake_clean.amplitude_events ae
        where et in ('Affiliate-Lead_referred',
                        'Refer-Lead_referred' )
            and	ym >= '2018-05'
            and regexp_like(e__lead_id, '(^\d+)')
    -- enriching with amplitude from SPARK processing
    union
        select
            cast(regexp_extract(
                coalesce(cast(json_extract(event_properties, '$.Lead_id') as varchar), '')
                , '(^\d+)') as bigint) as id_lead,
            null as firestore_id,
            null as e_formfield_lead_uuid,
            2 as rule_num,
            'referral_2' as rule,
            event_time,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
            coalesce(region, '') as region,
            coalesce(city, '') as city,
            coalesce(uuid, '') as uuid
    from datalake_clean_spark.amplitude_events
        where event_type in ('Affiliate-Lead_referred', 'Refer-Lead_referred' )
            and	year >= 2019
            and regexp_like(cast(json_extract(event_properties, '$.Lead_id') as varchar), '(^\d+)')
    ), prep_3 as (
    select 	null as id_lead,
            u_lead_firestore_id as firestore_id,
            null as e_formfield_lead_uuid,
            3 as rule_num,
            'firestore' as rule,
            event_time,
            u_initial_utm_campaign,
            u_initial_utm_medium,
            u_initial_utm_source,
            u_initial_utm_content,
            u_initial_utm_term,
            u_platform,
            region,
            city,
            uuid
    from datalake_clean.amplitude_events ae
        where
            ym >= '2018-01'
            and app = '183047'
            and trim(u_lead_firestore_id) <> ''
    -- enriching with amplitude from SPARK processing
    union
    select
            null as id_lead,
            coalesce(cast(json_extract(user_properties, '$.lead_firestore_id') as varchar), '') as firestore_id,
            null as e_formfield_lead_uuid,
            3 as rule_num,
            'firestore' as rule,
            event_time,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
            coalesce(region, '') as region,
            coalesce(city, '') as city,
            coalesce(uuid, '') as uuid
    from datalake_clean_spark.amplitude_events
        where year >= 2019
            and app = 183047
            and json_extract(user_properties, '$.lead_firestore_id') is not null
    ), prep_4 as (
    select 	null as id_lead,
            null as firestore_id,
            ae.e_formfield_lead_uuid as e_formfield_lead_uuid,
            4 as rule_num,
            'formfield' as rule,
            event_time,
            u_initial_utm_campaign,
            u_initial_utm_medium,
            u_initial_utm_source,
            u_initial_utm_content,
            u_initial_utm_term,
            u_platform,
            region,
            city,
            uuid
    from datalake_clean.amplitude_events ae
        where
            et = 'lead_form_submitted'
            and ym >= '2018-01'
            and trim(app) = '183047'
            AND trim(ae.e_formfield_lead_uuid) <> ''
    -- enriching with amplitude from SPARK processing
    union
    select
            null as id_lead,
            null as firestore_id,
            coalesce(cast(json_extract(event_properties, '$.formfield_lead_uuid') as varchar), '') as e_formfield_lead_uuid,
            4 as rule_num,
            'formfield' as rule,
            event_time,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
            coalesce(region, '') as region,
            coalesce(city, '') as city,
            coalesce(uuid, '') as uuid
    from datalake_clean_spark.amplitude_events
        where  event_type = 'lead_form_submitted'
            and year >= 2019
            and app = 183047
            and json_extract(event_properties, '$.formfield_lead_uuid') is not null
    )
select
    *,
    rank() over(partition by id_lead order by event_time) as rn
from prep_1
union
select
    *,
    rank() over(partition by id_lead order by event_time) as rn
from prep_2
union
select
    *,
    rank() over(partition by firestore_id order by event_time) as rn
from prep_3
union
select
    *,
    rank() over(partition by e_formfield_lead_uuid order by event_time desc) as rn
from prep_4
)
select
	id_lead,
    firestore_id,
    e_formfield_lead_uuid,
    rule_num,
    event_time,
    u_initial_utm_campaign,
    u_initial_utm_medium,
    u_initial_utm_source,
    u_initial_utm_content,
    u_initial_utm_term,
    u_platform,
    region,
    city,
    uuid
from t_all
where rn = 1 