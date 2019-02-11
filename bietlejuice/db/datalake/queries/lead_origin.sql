select  cast(regexp_extract(e_lead_id, '(^\d+)') as bigint) as id_lead,
        null as firestore_id,
        null as e_formfield_lead_uuid,
        1 as rule_num,
        'referral' as rule,
        event_time,
        u_initial_utm_campaign,
        u_initial_utm_medium,
        u_initial_utm_source,
        u_platform,
        region,
        city,
        uuid,
        rank() over(partition by e_lead_id order by event_time) as rn
from datalake_clean.amplitude_events ae
    where et in
        ('referral_confirmation_page_viewed',
        'referral_opportunity_confirmed',
        'referral_listing_confirmed',
        'referral_form_response_received')
        and	ym >= '2018-05'
        and ae.app = '205027'
        and regexp_like(e_lead_id, '(^\d+)') -- 379949 rows
union
select 	cast(regexp_extract(e__lead_id, '(^\d+)') as bigint) as id_lead,
        null as firestore_id,
        null as e_formfield_lead_uuid,
        2 as rule_num,
        'referral_2' as rule,
        event_time,
        u_initial_utm_campaign,
        u_initial_utm_medium,
        u_initial_utm_source,
        u_platform,
        region,
        city,
        uuid,
        rank() over(partition by e__lead_id order by event_time) as rn
from datalake_clean.amplitude_events ae
    where et in ('Affiliate-Lead_referred',
                    'Refer-Lead_referred' )
        and	ym >= '2018-05'
        and regexp_like(e__lead_id, '(^\d+)') --15475 rows
union
select 	null as id_lead,
        u_lead_firestore_id as firestore_id,
        null as e_formfield_lead_uuid,
        3 as rule_num,
        'firestore' as rule,
        event_time,
        u_initial_utm_campaign,
        u_initial_utm_medium,
        u_initial_utm_source,
        u_platform,
        region,
        city,
        uuid,
        rank() over(partition by u_lead_firestore_id order by event_time) as rn
from datalake_clean.amplitude_events ae
    where
        ym >= '2018-01'
        and app = '183047'
        and trim(u_lead_firestore_id) <> '' --2732620 rows
union
select 	null as id_lead,
        null as firestore_id,
        ae.e_formfield_lead_uuid as e_formfield_lead_uuid,
        4 as rule_num,
        'formfield' as rule,
        event_time,
        u_initial_utm_campaign,
        u_initial_utm_medium,
        u_initial_utm_source,
        u_platform,
        region,
        city,
        uuid,
        rank() over(partition by ae.e_formfield_lead_uuid order by event_time desc) as rn
from datalake_clean.amplitude_events ae
    where
        et = 'lead_form_submitted'
        and ym >= '2018-01'
        and trim(app) = '183047'
        AND trim(ae.e_formfield_lead_uuid) <> '' -- 50154 rows