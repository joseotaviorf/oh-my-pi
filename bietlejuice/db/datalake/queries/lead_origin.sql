with t_all as (
	with app_205027 as (
	            select  ep_lead_id,
	                    ts_event,
	                    up_initial_utm_campaign,
	                    up_initial_utm_medium,
	                    up_initial_utm_source,
	                    up_initial_utm_content,
	                    up_initial_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_confirmation_page_viewed_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            union
	            select  ep_lead_id,
	                    ts_event,
	                    up_initial_utm_campaign,
	                    up_initial_utm_medium,
	                    up_initial_utm_source,
	                    up_initial_utm_content,
	                    up_initial_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_opportunity_confirmed_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            union
	            select  ep_lead_id,
	                    ts_event,
	                    up_initial_utm_campaign,
	                    up_initial_utm_medium,
	                    up_initial_utm_source,
	                    up_initial_utm_content,
	                    up_initial_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_listing_confirmed_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            union
	            select  ep_lead_id,
	                    ts_event,
	                    up_initial_utm_campaign,
	                    up_initial_utm_medium,
	                    up_initial_utm_source,
	                    up_initial_utm_content,
	                    up_initial_utm_term,
	                    up_platform,
	                    up_referring_domain,
	                    region,
	                    city,
	                    uuid
	            from    datalake_amplitude_clean_prod."205027_referral_form_response_received_events"
	            where regexp_like(cast(ep_lead_id as varchar), '(^\d+)')
	            ),app_183047 as (
		            select  ep_formfield_lead_uuid,
		                    event_properties,
		                    ts_event,
		                    up_initial_utm_campaign,
		                    up_initial_utm_medium,
		                    up_initial_utm_source,
		                    up_initial_utm_content,
		                    up_initial_utm_term,
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
		                    up_initial_utm_campaign,
		                    up_initial_utm_medium,
		                    up_initial_utm_source,
		                    up_initial_utm_content,
		                    up_initial_utm_term,
		                    up_platform,
		                    up_referring_domain,
		                    region,
		                    city,
		                    uuid
		            from    datalake_amplitude_clean_prod."183047_price_suggestion_form_submitted_events"
		            where   ep_formfield_lead_uuid is not null
	            ),prep_ref as (
		            select
				            cast(regexp_extract(
				                coalesce(cast(ep_lead_id as varchar), '')
				                , '(^\d+)') as bigint) as id_lead,
				            null as firestore_id,
				            null as e_formfield_lead_uuid,
				            1 as rule_num,
				            'referral' as rule,
				            ts_event,
				            coalesce(cast(up_initial_utm_campaign as varchar), '') as u_initial_utm_campaign,
				            coalesce(cast(up_initial_utm_medium as varchar), '') as u_initial_utm_medium,
				            coalesce(cast(up_initial_utm_source as varchar), '') as u_initial_utm_source,
				            coalesce(cast(up_initial_utm_content as varchar), '') as u_initial_utm_content,
				            coalesce(cast(up_initial_utm_term as varchar), '') as u_initial_utm_term,
				            coalesce(cast(up_platform as varchar), '') as platform,
				            coalesce(cast(up_referring_domain as varchar), '') as u_referring_domain,
				            coalesce(region, '') as region,
				            coalesce(city, '') as city,
				            coalesce(uuid, '') as uuid
				    from 	app_205027
			    ),prep_ref_2 as (
			        select
				            cast(regexp_extract(
				                coalesce(cast(json_extract(event_properties, '$.Lead_id') as varchar), '')
				                , '(^\d+)') as bigint) as id_lead,
				            null as firestore_id,
				            null as e_formfield_lead_uuid,
				            2 as rule_num,
				            'referral_2' as rule,
				            ts_event,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
				            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
				            coalesce(cast(json_extract(user_properties, '$.referring_domain') as varchar), '') as u_referring_domain,
				            coalesce(region, '') as region,
				            coalesce(city, '') as city,
				            coalesce(uuid, '') as uuid
			    	from 	datalake_amplitude_clean_prod.events_repartitioned
			    	where 	event_type in ('Affiliate-Lead_referred', 'Refer-Lead_referred' )
			            and regexp_like(cast(json_extract(event_properties, '$.Lead_id') as varchar), '(^\d+)')
			    ), prep_firestore as (
				    select
				            null as id_lead,
				            coalesce(cast(json_extract(user_properties, '$.lead_firestore_id') as varchar), '') as firestore_id,
				            null as e_formfield_lead_uuid,
				            3 as rule_num,
				            'firestore' as rule,
				            ts_event,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_campaign') as varchar), '') as u_initial_utm_campaign,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_medium') as varchar), '') as u_initial_utm_medium,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_source') as varchar), '') as u_initial_utm_source,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_content') as varchar), '') as u_initial_utm_content,
				            coalesce(cast(json_extract(user_properties, '$.initial_utm_term') as varchar), '') as u_initial_utm_term,
				            coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as platform,
				            coalesce(cast(json_extract(user_properties, '$.referring_domain') as varchar), '') as u_referring_domain,
				            coalesce(region, '') as region,
				            coalesce(city, '') as city,
				            coalesce(uuid, '') as uuid
				    from datalake_amplitude_clean_prod.events
				        where id_app = 183047
				            and json_extract(user_properties, '$.lead_firestore_id') is not null
				), prep_form as (
					select
		                    null as id_lead,
		                    null as firestore_id,
		                    coalesce(cast(ep_formfield_lead_uuid as varchar), '') as e_formfield_lead_uuid,
		                    4 as rule_num,
		                    'formfield' as rule,
		                    ts_event,
		                    coalesce(cast(up_initial_utm_campaign as varchar), '') as u_initial_utm_campaign,
		                    coalesce(cast(up_initial_utm_medium as varchar), '') as u_initial_utm_medium,
		                    coalesce(cast(up_initial_utm_source as varchar), '') as u_initial_utm_source,
		                    coalesce(cast(up_initial_utm_content as varchar), '') as u_initial_utm_content,
		                    coalesce(cast(up_initial_utm_term as varchar), '') as u_initial_utm_term,
		                    coalesce(cast(up_platform as varchar), '') as platform,
		                    coalesce(cast(up_referring_domain as varchar), '') as u_referring_domain,
		                    coalesce(region, '') as region,
		                    coalesce(city, '') as city,
		                    coalesce(uuid, '') as uuid
		            from    app_183047
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
					)select
							id_lead,
						    firestore_id,
						    e_formfield_lead_uuid,
						    rule_num,
						    ts_event,
						    u_initial_utm_campaign,
						    u_initial_utm_medium,
						    u_initial_utm_source,
						    u_initial_utm_content,
						    u_initial_utm_term,
						    platform as u_platform,
						    u_referring_domain,
						    region,
						    city,
					    	uuid
					from 	t_all
					where 	rn = 1