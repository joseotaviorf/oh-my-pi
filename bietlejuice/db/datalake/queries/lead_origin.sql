with t_all as (
	with app_205027 as (
	            select  ep_lead_id,
	                    ts_event,
	                    up_utm_campaign,
	                    up_utm_medium,
	                    up_utm_source,
	                    up_utm_content,
	                    up_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_form_accepted_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            union
	            select  ep_lead_id,
	                    ts_event,
	                    up_utm_campaign,
	                    up_utm_medium,
	                    up_utm_source,
	                    up_utm_content,
	                    up_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_form_discarded_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            )
	,app_183047 as (
                select  ep_formfield_lead_uuid,
                        event_properties,
                        ts_event,
                        up_utm_campaign,
                        up_utm_medium,
                        up_utm_source,
                        up_utm_content,
                        up_utm_term,
                        up_platform,
                        up_referring_domain,
                        region,
                        city,
                        uuid
                from    datalake_amplitude_clean_prod."183047_lead_form_submitted_events"
                where   ep_formfield_lead_uuid is not null
                union
                select ep_formfield_lead_uuid,
                        event_properties,
                        ts_event,
                        up_utm_campaign,
                        up_utm_medium,
                        up_utm_source,
                        up_utm_content,
                        up_utm_term,
                        up_platform,
                        up_referring_domain,
                        region,
                        city,
                        uuid
                from    datalake_amplitude_clean_prod."183047_price_suggestion_form_submitted_events"
                where   ep_formfield_lead_uuid is not null
                union
                select ep_formfield_lead_uuid,
                        event_properties,
                        ts_event,
                        up_utm_campaign,
                        up_utm_medium,
                        up_utm_source,
                        up_utm_content,
                        up_utm_term,
                        up_platform,
                        up_referring_domain,
                        region,
                        city,
                        uuid
                from    datalake_amplitude_clean_prod."183047_price_suggestion_sale_form_submitted_events"
                where   ep_formfield_lead_uuid is not null
	            )
    ,prep_ref as (
                select
                        cast(regexp_extract(
                            coalesce(cast(ep_lead_id as varchar), '')
                            , '(^\d+)') as bigint) as id_lead,
                        null as firestore_id,
                        null as e_formfield_lead_uuid,
                        1 as rule_num,
                        'referral' as rule,
                        ts_event,
                        coalesce(cast(up_utm_campaign as varchar), '') as up_utm_campaign,
                        coalesce(cast(up_utm_medium as varchar), '') as up_utm_medium,
                        coalesce(cast(up_utm_source as varchar), '') as up_utm_source,
                        coalesce(cast(up_utm_content as varchar), '') as up_utm_content,
                        coalesce(cast(up_utm_term as varchar), '') as up_utm_term,
                        coalesce(cast(up_platform as varchar), '') as up_platform,
                        coalesce(cast(up_referring_domain as varchar), '') as up_referring_domain,
                        coalesce(region, '') as region,
                        coalesce(city, '') as city,
                        coalesce(uuid, '') as uuid
                from 	app_205027
			    )
    ,prep_ref_2 as (
                select
                        cast(regexp_extract(
                            coalesce(cast(json_extract(event_properties, '$.Lead_id') as varchar), '')
                            , '(^\d+)') as bigint) as id_lead,
                        null as firestore_id,
                        null as e_formfield_lead_uuid,
                        2 as rule_num,
                        'referral_2' as rule,
                        ts_event,
                        coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as up_utm_campaign,
                        coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as up_utm_medium,
                        coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as up_utm_source,
                        coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as up_utm_content,
                        coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as up_utm_term,
                        coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as up_platform,
                        coalesce(cast(json_extract(user_properties, '$.referring_domain') as varchar), '') as up_referring_domain,
                        coalesce(region, '') as region,
                        coalesce(city, '') as city,
                        coalesce(uuid, '') as uuid
                from 	datalake_amplitude_clean_prod.events
                where 	event_type in ('Affiliate-Lead_referred', 'Refer-Lead_referred' )
                    and regexp_like(cast(json_extract(event_properties, '$.Lead_id') as varchar), '(^\d+)')
			    )
    ,prep_firestore_tmp as (
                select
                        null as id_lead,
                        coalesce(cast(json_extract(user_properties, '$.lead_firestore_id') as varchar), '') as firestore_id,
                        null as e_formfield_lead_uuid,
                        3 as rule_num,
                        'firestore' as rule,
                        ts_event,
                        coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as up_utm_campaign,
                        coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as up_utm_medium,
                        coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as up_utm_source,
                        coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as up_utm_content,
                        coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as up_utm_term,
                        coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as up_platform,
                        coalesce(cast(json_extract(user_properties, '$.referring_domain') as varchar), '') as up_referring_domain,
                        coalesce(region, '') as region,
                        coalesce(city, '') as city,
                        coalesce(uuid, '') as uuid
                from datalake_amplitude_clean_prod.events
                    where id_app = 183047
                        and json_extract(user_properties, '$.lead_firestore_id') is not null
				)
	, prep_firestore as (
        select
            id_lead,
            coalesce(rene.id, prep_firestore_tmp.firestore_id) as firestore_id,
            e_formfield_lead_uuid,
            rule_num,
            rule,
            ts_event,
            up_utm_campaign,
            up_utm_medium,
            up_utm_source,
            up_utm_content,
            up_utm_term,
            up_platform,
            up_referring_domain,
            region,
            city,
            uuid
        from prep_firestore_tmp 
        left join datalake_rene_descartes_clean_prod.house_lead rene
        on rene.id_external_reference = prep_firestore_tmp.firestore_id and date(ts_event) >= date('2021-07-15') -- On 2021-07-15 a change was made by the Product Team, the firestore_id is no longer being inserted on datalake_amplitude_clean_prod.events, but in datalake_rene_descartes_clean_prod.house_lead
    )
    , prep_form as (
                select
                        null as id_lead,
                        null as firestore_id,
                        coalesce(rene.id, cast(ep_formfield_lead_uuid as varchar), '') as e_formfield_lead_uuid,
                        4 as rule_num,
                        'formfield' as rule,
                        ts_event,
                        coalesce(cast(up_utm_campaign as varchar), '') as up_utm_campaign,
                        coalesce(cast(up_utm_medium as varchar), '') as up_utm_medium,
                        coalesce(cast(up_utm_source as varchar), '') as up_utm_source,
                        coalesce(cast(up_utm_content as varchar), '') as up_utm_content,
                        coalesce(cast(up_utm_term as varchar), '') as up_utm_term,
                        coalesce(cast(up_platform as varchar), '') as up_platform,
                        coalesce(cast(up_referring_domain as varchar), '') as up_referring_domain,
                        coalesce(region, '') as region,
                        coalesce(city, '') as city,
                        coalesce(uuid, '') as uuid
                from    app_183047
                left join datalake_rene_descartes_clean_prod.house_lead rene
                on rene.id_external_reference = app_183047.ep_formfield_lead_uuid and date(app_183047.ts_event) >= date('2021-07-15') -- On 2021-07-15 a change was made by the Product Team, the ep_formfield_lead_uuid is no longer being inserted on datalake_amplitude_clean_prod.events, but in datalake_rene_descartes_clean_prod.house_lead
                )
    select
        *,
        rank() over(partition by id_lead order by ts_event) as rn
    from prep_ref
    union
    select
        *,
        rank() over(partition by id_lead order by ts_event) as rn
    from prep_ref_2
    union
    select
        *,
        rank() over(partition by firestore_id order by ts_event) as rn
    from prep_firestore
    union
    select
        *,
        rank() over(partition by e_formfield_lead_uuid order by ts_event desc) as rn
    from prep_form
)
select
        id_lead,
        firestore_id,
        e_formfield_lead_uuid,
        rule_num,
        ts_event,
        substr(up_utm_campaign, 1, 250) as up_utm_campaign,
        substr(up_utm_medium, 1, 250) as up_utm_medium,
        substr(up_utm_source, 1, 250) as up_utm_source,
        substr(up_utm_content, 1, 250) as up_utm_content,
        substr(up_utm_term, 1, 250) as up_utm_term,
        up_platform,
        up_referring_domain,
        region,
        city,
        uuid
from 	t_all
where 	rn = 1