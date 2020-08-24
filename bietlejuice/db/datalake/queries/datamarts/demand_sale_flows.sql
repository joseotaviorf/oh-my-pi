-- A Sale Flow is defined by the tuple buyer <> house . It can start with three possible events (BOOKING, TALK TO AGENT OR DIRECT OFFER) -- 
with taxonomy_demand as (
	with
	taxonomy_min_ids as (
		select
		min(id) as id
		from datalake_raw.gsheets_taxonomy_demand
		where first_update_source = 'Inquilinos'
		    and flg_via_reschedule = '0'
		group by
			lower(app_type),
			lower(utm_source),
			lower(utm_medium),
			lower(branded),
			lower(first_update_source),
            		flg_via_reschedule
	)
	 select
	    cast(td.id as bigint) as id,
		td.app_type,
		td.utm_source,
		td.utm_medium,
		td.branded,
		td.Category as mkt_category,
		td.Flow as mkt_flow,
		td.Completion as mkt_completion,
		td.Channel as mkt_channel,
		td.Medium as mkt_medium,
		td.Origin as mkt_origin,
		td.Source as mkt_source,
		td.Platform as mkt_platform
	from datalake_raw.gsheets_taxonomy_demand td
	join taxonomy_min_ids td_min
		on td.id = td_min.id
)
, events_raw_offer as (
    select 
        distinct
		id_user||'_'||json_extract_scalar(event_properties, '$.house_id') as sale_flow,
		cast(trim(json_extract_scalar(evt.event_properties, '$.house_id')) as integer) as id_house,
		cast(evt.id_user as integer) as id_user,
		cast(trim(json_extract_scalar(event_properties, '$.offer_id')) as varchar) as id_offer,
        	json_extract_scalar(user_properties, '$["utm_source"]') as utm_source,
    		json_extract_scalar(user_properties, '$["utm_medium"]') as utm_medium,
    		json_extract_scalar(user_properties, '$["utm_campaign"]') as utm_campaign,
    		case 
    	    		when (UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%BRANDED%'
    			or UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%INSTITUCIONAL%')
    			and UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) not like '%NON-BRANDED%'
                		then 'Branded'
            		else 'Outro'
    		end as branded,
    		json_extract_scalar(user_properties , '$["platform"]') as app_type,
        	cast(ts_event as timestamp) as event_timestamp
    from datalake_amplitude_clean_prod.events evt
	where
		evt.event_type = 'sale_offer_form_accepted' 
		and evt.id_app = 170698
)
, events_raw_tta as (
    select 
        distinct
		id_user||'_'||json_extract_scalar(event_properties, '$.house_id') as sale_flow,
		cast(trim(json_extract_scalar(evt.event_properties, '$.house_id')) as integer) as id_house,
		cast(evt.id_user as integer) as id_user,
		cast(json_extract_scalar(event_properties, '$.agent_id') as integer) as id_agent,
        	json_extract_scalar(user_properties, '$["utm_source"]') as utm_source,
    		json_extract_scalar(user_properties, '$["utm_medium"]') as utm_medium,
    		json_extract_scalar(user_properties, '$["utm_campaign"]') as utm_campaign,
    		case 
    	    		when (UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%BRANDED%'
    			or UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%INSTITUCIONAL%')
    			and UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) not like '%NON-BRANDED%'
                		then 'Branded'
            		else 'Outro'
    		end as branded,
    	json_extract_scalar(user_properties , '$["platform"]') as app_type,
        cast(ts_event as timestamp) as event_timestamp
    from datalake_amplitude_clean_prod.events evt
    -- Filter events made by sale agents and houses listed for Sale 
    join datalake_clean.ods_dim_user sa
	on cast(json_extract_scalar(evt.event_properties, '$.agent_id') as integer) = cast(sa.id as integer) 
	and sa.is_sale_agent = 'True'
    join datalake_ebdb_clean_prod.listing_business_context lbc 
	on cast(json_extract_scalar(evt.event_properties, '$.house_id') as integer) = lbc.id_house
	and lbc.business_context = 'SALE'
    where
	    event_type = 'piloto_cw_message_sent' 
	    and ts_event > timestamp '2020-03-01 00:00' --month start of the feature
	    and evt.id_app = 170698
	    and id_user||'_'||json_extract_scalar(event_properties, '$.house_id') is not null
)
-- Taxonomy from the first event of the sale flow
, sf_events as (
	select
	    evt.sale_flow,
	    td.app_type,
	    td.utm_source,
	    td.utm_medium,
	    evt.branded = 'Branded' as flg_branded,
	    td.mkt_category,
	    td.mkt_flow,
	    td.mkt_completion,
	    td.mkt_origin,
	    td.mkt_channel,
	    td.mkt_medium,
	    td.mkt_source,
	    td.mkt_platform,
	    evt.utm_campaign,
		evt.event_timestamp
	from events_raw_offer evt
	left join taxonomy_demand td
	    on lower(coalesce(td.app_type,'')) = lower(coalesce(evt.app_type,''))
		and lower(coalesce(td.utm_source,'')) = lower(coalesce(evt.utm_source,''))
		and lower(coalesce(td.utm_medium,'')) = lower(coalesce(evt.utm_medium,''))
		and lower(coalesce(td.branded,'')) = lower(coalesce(evt.branded,''))
	union all
		select
	    evt.sale_flow,
	    td.app_type,
	    td.utm_source,
	    td.utm_medium,
	    evt.branded = 'Branded' as flg_branded,
	    td.mkt_category,
	    td.mkt_flow,
	    td.mkt_completion,
	    td.mkt_origin,
	    td.mkt_channel,
	    td.mkt_medium,
	    td.mkt_source,
	    td.mkt_platform,
	    evt.utm_campaign,
		evt.event_timestamp
	from events_raw_tta evt
	left join taxonomy_demand td
	    on lower(coalesce(td.app_type,'')) = lower(coalesce(evt.app_type,''))
		and lower(coalesce(td.utm_source,'')) = lower(coalesce(evt.utm_source,''))
		and lower(coalesce(td.utm_medium,'')) = lower(coalesce(evt.utm_medium,''))
		and lower(coalesce(td.branded,'')) = lower(coalesce(evt.branded,''))
	union all
	select
		a.id_visitor||'_'||a.id_property as sale_flow,
	    a.app_type,
	    a.utm_source,
	    a.utm_medium,
	    cast(a.flg_branded as boolean) as flg_branded,
	    a.mkt_category,
	    a.mkt_flow,
	    a.mkt_completion,
	    a.mkt_origin,
	    a.mkt_channel,
	    a.mkt_medium,
	    a.mkt_source,
	    a.mkt_platform,
	    a.utm_campaign,
	    date_parse(nullif(a.dt_created, ''), '%Y-%m-%d %H:%i:%s') as event_timestamp
	from datalake_clean.ods_dim_booking a
	where
		a.visit_intent = 'SALE'
		and a.type = 'Visita'
)
, sale_flow_taxonomy as (
	select
		sf.sale_flow,
	    sf.app_type,
	    sf.utm_source,
	    sf.utm_medium,
	    sf.flg_branded,
	    sf.mkt_category,
	    sf.mkt_flow,
	    sf.mkt_completion,
	    sf.mkt_origin,
	    sf.mkt_channel,
	    sf.mkt_medium,
	    sf.mkt_source,
	    sf.mkt_platform,
	    sf.utm_campaign,
	    sf.event_timestamp,
	    row_number() over(partition by sf.sale_flow order by sf.event_timestamp) as flow_order
	from sf_events sf
)
-- Bookings and visits - first dates and counts
, booking as (
	select
		a.id_visitor||'_'||a.id_property as sale_flow, 
		cast(a.id_visitor as integer) as id_user,
		cast(a.id_property as integer) as id_house,
		min(date_parse(nullif(a.dt_created, ''), '%Y-%m-%d %H:%i:%s')) as ts_first_booking_created,
		min(case when a.visit_follow_up = 'VaiNegociar' then date_parse(nullif(a.dt_scheduling, ''), '%Y-%m-%d %H:%i:%s') end) as ts_first_visit_completed,
		count(distinct a.id_booking) as nbr_bookings,
		count(distinct case when a.visit_follow_up = 'VaiNegociar' then a.id_booking end) as nbr_visits_completed
	from datalake_clean.ods_dim_booking a
	where
		a.visit_intent = 'SALE'
		and a.type = 'Visita'
	group by 1, 2, 3
)
-- Talk to agent messages sent and attendances - first dates and counts
, sale_tta_messages as (
	select
		tta.sale_flow,
		tta.id_house,
		tta.id_user,
		min(event_timestamp) as ts_first_tta_message_sent,
		count(event_timestamp) as nbr_tta_messages
	from events_raw_tta tta
	group by 1, 2, 3
)
, sale_tta_attendance as (
	select 
		cast(ags.id_user as varchar)||'_'||cast(lbc.id_house as varchar) as sale_flow,
		lbc.id_house,
		ags.id_user,
		min(ags.ts_created) as ts_first_tta_attendance,
		count(distinct ags.id) as nbr_tta_attendance
	from datalake_ebdb_clean_prod.agent_support ags 
	join datalake_ebdb_clean_prod.listing_business_context lbc
		on ags.id_listing = lbc.id
	where 
		 lbc.business_context = 'SALE'
		and ags.status = 'COMPLETE' -- only completed agent attendance
	group by 1, 2, 3
)
, talk_to_agent as (
	select 
		tm.sale_flow,
		tm.id_house,
		tm.id_user,
		tm.ts_first_tta_message_sent,
		ta.ts_first_tta_attendance,
		tm.nbr_tta_messages,
		coalesce(ta.nbr_tta_attendance,0) as nbr_tta_attendances
	from sale_tta_messages tm 
	left join sale_tta_attendance ta
		on ta.sale_flow = tm.sale_flow
)
-- Offers - first dates and counts
-- We get ts_offer_sent from amplitude event as we don't have timestamp in Monday gsheets. 
-- Also events in amplitude are set to UTC timezone (same as VB and TTA) and monday events are set to BRT timezone. So, we can't adjust while we don't have timestamps (temporary solution)
-- Treat data from Monday gsheets
, treat_monday as (
	select 
		nullif(mo.name,'') as id_offer,
		mo.id_buyer||'_'||mo.id_imovel as sale_flow,
		cast(nullif(mo.id_imovel,'') as integer) as id_house,
		cast(nullif(mo.id_buyer,'') as integer) as id_user,
		date_parse(substring(nullif(mo.data_proposta, ''),1,10), '%Y-%m-%d') as dt_offer_sent,
		date_parse(substring(nullif(mo.data_aceite_proposta, ''),1,10), '%Y-%m-%d') as dt_offer_accepted,
		date_parse(substring(nullif(mo.data_assinatura_ccv, ''),1,10), '%Y-%m-%d') as dt_ccv_signed,
		date_parse(substring(nullif(mo.data_descarte, ''),1,10), '%Y-%m-%d') as dt_offer_rejected,
		date_parse(substring(nullif(mo.data_pagto_seller, ''),1,10), '%Y-%m-%d') as dt_payment_completed,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_proposta,''), 1, 10), '-', '') as integer),-1) as sk_offer_sent_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_aceite_proposta, ''), 1, 10), '-', '') as integer),-1) as sk_offer_accepted_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_assinatura_ccv, ''), 1, 10), '-', '') as integer),-1) as sk_ccv_signed_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_descarte, ''), 1, 10), '-', '') as integer),-1) as sk_offer_rejected_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_pagto_seller, ''), 1, 10), '-', '') as integer),-1) as sk_payment_completed_date,
		case when mo.grupo = 'CCV - Cancelado' then true else false end as flg_ccv_cancelled,
		motivo_descarte_pre as offer_rejection_reason,
		motivo_descarte_pos as offer_accepted_drop_reason,
		status_proposta,
		cast(nullif(mo.valor_anuncio, '') as integer) as sale_listing_price,
		cast(nullif(mo.proposta_buyer, '') as integer) as buyer_offer_price,
		cast(nullif(mo.valor_final, '') as integer) as sale_price_agreed,
		case when mo.valor_anuncio ='' or mo.proposta_buyer ='' then null else (cast(mo.valor_anuncio as decimal) - cast(mo.proposta_buyer as decimal))*1.00/cast(mo.valor_anuncio as decimal) end as offer_discount
	from datalake_raw.gsheets_sale_offers_monday mo  
)
-- Remove duplicates (invalid offers) from Monday gsheets
, fix_monday as (
	select 
	    tm.sale_flow,
	    tm.id_house,
	    tm.id_user,
	    max(tm.dt_offer_accepted) as dt_offer_accepted,
	    max(tm.dt_offer_rejected) as dt_offer_rejected,
	    max(tm.dt_ccv_signed) as dt_ccv_signed,
	    max(tm.dt_payment_completed) as dt_payment_completed,
	    max(tm.sk_offer_accepted_date) as sk_offer_accepted_date,
	    max(tm.sk_offer_rejected_date) as sk_offer_rejected_date,
	    max(tm.sk_ccv_signed_date) as sk_ccv_signed_date,
	    max(tm.sk_payment_completed_date) as sk_payment_completed_date,
	    max(flg_ccv_cancelled) as flg_ccv_cancelled,
	    max(tm.offer_rejection_reason) as offer_rejection_reason,
	    max(tm.offer_accepted_drop_reason) as offer_accepted_drop_reason,
	    max(tm.sale_listing_price) as sale_listing_price,
	    max(tm.buyer_offer_price) as buyer_offer_price,
	    max(tm.sale_price_agreed) as sale_price_agreed,
	    max(tm.offer_discount) as offer_discount
	from treat_monday tm
	group by 1, 2, 3
)
-- First We search the offer data from amplitude (less errors with id_users/nulls). Otherwise if there's an id_offer only present in Monday we bring monday data
, offer_sent as (
	select
		coalesce(o.sale_flow, fm.sale_flow) as sale_flow,
		coalesce(o.id_house, fm.id_house) as id_house,
		coalesce(o.id_user, fm.id_user) as id_user,
		coalesce(min(o.event_timestamp),min(fm.dt_offer_sent)) as ts_first_offer_sent,
		count(distinct coalesce(o.id_offer, fm.id_offer)) as nbr_offers_sent
	from events_raw_offer o
	full outer join treat_monday fm
		on fm.id_offer = o.id_offer
	group by 1, 2, 3
)
-- Count the order of the offer sent by the buyer
, buyer_offers as (
	select 
		os.sale_flow,
		os.id_house,
		os.id_user,
		os.ts_first_offer_sent,
		row_number() over (partition by os.id_user order by ts_first_offer_sent) as rw_buyer_offer_sent,
		row_number() over (partition by os.id_house order by ts_first_offer_sent) as rw_house_offer_sent
	from offer_sent os
)
, sellers_info as (
	select 
		h.id_user as id_seller,
		h.id as id_house,
		h.status,
		fl.sk_region
	from datalake_ebdb_clean_prod.house h
	join datalake_ebdb_clean_prod.listing_business_context lbc 
		on lbc.id_house = h.id 
	join datalake_clean.ods_sale_fact_listing_flows fl
		on cast(trim(fl.sk_house_listing) as bigint)/1000 = h.id
		and cast(trim(fl.sk_house_listing) as bigint) > 0
	where
		lbc.business_context = 'SALE'
)
-- Listing actual status (Sale and Rent)
, listings_status as (
    select 
        si.id_house,
        si.id_seller,
        cast(si.sk_region as integer) as sk_region,
        max(case when lbc.business_context = 'RENT' then si.status end) as house_status_rent,
        max(case when lbc.business_context = 'SALE' then lbc.status end) as house_status_sale,
        max(case when lbc.business_context = 'RENT' then lbc.status_reason end) as house_status_reason_rent,
        max(case when lbc.business_context = 'SALE' then lbc.status_reason end) as house_status_reason_sale
    from sellers_info si 
    join datalake_ebdb_clean_prod.listing_business_context lbc 
    	on lbc.id_house = si.id_house
    group by 1 , 2, 3
)
-- Put all sale_flows togheter
, sale_flows as (
	select
		coalesce(b.sale_flow, o.sale_flow, tta.sale_flow) as sale_flow,
		coalesce(b.id_user, o.id_user, tta.id_user) as id_buyer,
		coalesce(b.id_house, o.id_house, tta.id_house) as id_house,
		case 
			when least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), -- timestamp '2030-01-01' to avoid nulls in the function "least"
				coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), 
				coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01')) = b.ts_first_booking_created 
					then 'booking'
			when least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), 
				coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), 
				coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01')) = tta.ts_first_tta_message_sent 
					then 'talk_to_agent'
			when least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), 
				coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), 
				coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01')) = o.ts_first_offer_sent 
					then 'offer'
			else null
		end as first_event,
		least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01')) as ts_first_event,
		b.ts_first_booking_created,
		b.ts_first_visit_completed,
		tta.ts_first_tta_message_sent,
		tta.ts_first_tta_attendance,
		o.ts_first_offer_sent,
		coalesce(b.nbr_bookings,0) as nbr_bookings,
		coalesce(b.nbr_visits_completed,0) as nbr_visits_completed,
		coalesce(tta.nbr_tta_messages,0) as nbr_tta_messages,
		coalesce(tta.nbr_tta_attendances,0) as nbr_tta_attendances,
		coalesce(o.nbr_offers_sent,0) as nbr_offers_sent,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01')),'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER),-1) as sk_first_event,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(b.ts_first_booking_created,'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER), -1) as sk_first_booking_created_date,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(b.ts_first_visit_completed,'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER), -1) as sk_first_visit_completed_date,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(tta.ts_first_tta_message_sent,'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER), -1) as sk_first_tta_message_sent,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(tta.ts_first_tta_attendance,'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER), -1) as sk_first_tta_attendance_date,
		coalesce(CAST(REPLACE(SUBSTRING(to_char(o.ts_first_offer_sent,'yyyy-mm-dd'), 1, 10), '-', '') as INTEGER), -1) as sk_first_offer_sent_date,
		row_number() over (partition by coalesce(b.id_user, o.id_user, tta.id_user) order by least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01'))) as rw_buyer_sale_flow,
		row_number() over (partition by coalesce(b.id_house, o.id_house, tta.id_house) order by least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01'))) as rw_house_sale_flow
	from booking b
	full outer join offer_sent o
		on b.sale_flow = o.sale_flow
	full outer join talk_to_agent tta
		on coalesce(b.sale_flow, o.sale_flow) = tta.sale_flow
)
-- flag's rules and categories
select 
	b.sale_flow,
	b.id_buyer,
	b.id_house,
	si.id_seller,
	si.sk_region,												      
	b.first_event,
	-- gets the higher intent before the offer submission (VC > VB > TTA > DO)
	case 
		when sk_first_offer_sent_date = -1 
			then null
		when sk_first_offer_sent_date >= sk_first_visit_completed_date and sk_first_visit_completed_date > 0
			then 'VC_before_OS'
		when sk_first_offer_sent_date >= sk_first_booking_created_date and sk_first_booking_created_date > 0
			then 'VB_before_OS'
		when sk_first_offer_sent_date >= sk_first_tta_message_sent and sk_first_tta_message_sent > 0
			then 'TTA_before_OS'
		else 'Direct_Offer'
	end as higher_intent_before_offer,
	-- gets the higher intent after the offer submission (VC > VB > TTA > DO)
	case 
		when sk_first_offer_sent_date = -1 
			then null
		when sk_first_offer_sent_date < sk_first_visit_completed_date
			then 'VC_after_OS'
		when sk_first_offer_sent_date < sk_first_booking_created_date
			then 'VB_after_OS'
		when sk_first_offer_sent_date < sk_first_tta_message_sent
			then 'TTA_after_OS'
		else 'only_Offer'
	end as higher_intent_after_offer,
	case 
		when b.rw_buyer_sale_flow = 1 then true
		else false
	end as is_buyer_first_sale_flow,
	case 
		when bo.rw_buyer_offer_sent = 1 then true
		else false
	end as is_buyer_first_offer,
	case 
		when b.rw_house_sale_flow = 1 then true
		else false
	end as is_house_first_sale_flow,
	case 
		when bo.rw_house_offer_sent = 1 then true
		else false
	end as is_house_first_offer,
	 -- which events happened in this sale flow
	case 
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date > 0 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date > 0 
			then 'VB_VC_TTA_OS'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date > 0 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date = -1 
			then 'VB_VC_TTA'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date > 0 and sk_first_tta_message_sent = -1 and sk_first_offer_sent_date > 0 
			then 'VB_VC_OS'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date > 0 
			then 'VB_TTA_OS'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date > 0 and sk_first_tta_message_sent = -1 and sk_first_offer_sent_date = -1
			then 'VB_VC'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent = -1 and sk_first_offer_sent_date > 0 
			then 'VB_OS'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date = -1
			then 'VB_TTA'
		when sk_first_booking_created_date > 0 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent = -1 and sk_first_offer_sent_date = -1
			then 'VB'
		when sk_first_booking_created_date = -1 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date > 0
			then 'TTA_OS'
		when sk_first_booking_created_date = -1 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent > 0 and sk_first_offer_sent_date = -1
			then 'TTA'
		when sk_first_booking_created_date = -1 and sk_first_visit_completed_date = -1 and sk_first_tta_message_sent = -1 and sk_first_offer_sent_date > 0
			then 'OS'
		else null 
	end as flow_type, 
	 -- the order of the events 
	case 
		when first_event = 'booking' then 'VB'
		when first_event = 'talk_to_agent' then 'TTA'
		when first_event = 'offer' then 'OS'
		else ''
	end 
	||'.'||
	case 
		when first_event = 'booking' and least(coalesce(ts_first_visit_completed,timestamp '2030-01-01'), coalesce(b.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(ts_first_tta_message_sent,timestamp '2030-01-01')) = ts_first_visit_completed then 'VC'
		when first_event = 'booking' and least(coalesce(ts_first_visit_completed,timestamp '2030-01-01'), coalesce(b.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(ts_first_tta_message_sent,timestamp '2030-01-01')) = b.ts_first_offer_sent then 'OS'
		when first_event = 'booking' and least(coalesce(ts_first_visit_completed,timestamp '2030-01-01'), coalesce(b.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(ts_first_tta_message_sent,timestamp '2030-01-01')) = ts_first_tta_message_sent then 'TTA'
		when first_event = 'talk_to_agent' and least(coalesce(ts_first_booking_created,timestamp '2030-01-01'), coalesce(b.ts_first_offer_sent,timestamp '2030-01-01')) = ts_first_booking_created then 'VB'
		when first_event = 'talk_to_agent' and least(coalesce(ts_first_booking_created,timestamp '2030-01-01'), coalesce(b.ts_first_offer_sent,timestamp '2030-01-01')) = b.ts_first_offer_sent then 'OS'
		when first_event = 'offer' and least(coalesce(ts_first_booking_created,timestamp '2030-01-01'), coalesce(ts_first_tta_message_sent,timestamp '2030-01-01')) = ts_first_booking_created then 'VB'
		when first_event = 'offer' and least(coalesce(ts_first_booking_created,timestamp '2030-01-01'), coalesce(ts_first_tta_message_sent,timestamp '2030-01-01')) = ts_first_tta_message_sent then 'TTA'
		else ''
	end 
	||'.'||
	case 
		when ts_first_booking_created > greatest(b.ts_first_offer_sent, ts_first_tta_message_sent) and sk_first_offer_sent_date > 0 and sk_first_tta_message_sent > 0 then 'VB'
		when (ts_first_visit_completed > b.ts_first_offer_sent) and sk_first_booking_created_date > 0 and sk_first_offer_sent_date > 0  then 'VC'
		when (ts_first_visit_completed > ts_first_tta_message_sent) and sk_first_booking_created_date > 0 and sk_first_tta_message_sent > 0 then 'VC'
		when b.ts_first_offer_sent > ts_first_visit_completed and sk_first_visit_completed_date > 0 and sk_first_booking_created_date > 0  then 'OS'
		when b.ts_first_offer_sent > greatest(ts_first_tta_message_sent, ts_first_booking_created) and sk_first_booking_created_date > 0 and sk_first_tta_message_sent > 0 then 'OS'
		when ts_first_tta_message_sent > ts_first_visit_completed and sk_first_visit_completed_date > 0 and sk_first_booking_created_date > 0  then 'TTA'
		when ts_first_tta_message_sent > greatest( b.ts_first_offer_sent, ts_first_booking_created) and sk_first_booking_created_date > 0 and sk_first_offer_sent_date > 0 then 'TTA'
		else ''
	end 
	||'.'||
	case 
		when ts_first_visit_completed > greatest(b.ts_first_offer_sent, ts_first_tta_message_sent) and sk_first_offer_sent_date > 0 and sk_first_tta_message_sent > 0 then 'VC'
		when b.ts_first_offer_sent > greatest(ts_first_visit_completed, ts_first_tta_message_sent) and sk_first_visit_completed_date > 0 and sk_first_tta_message_sent > 0 then 'OS'
		when ts_first_tta_message_sent > greatest(b.ts_first_offer_sent, ts_first_visit_completed) and sk_first_offer_sent_date > 0 and sk_first_visit_completed_date  > 0 then 'TTA'
		else ''
	end as events_order,
	b.ts_first_event,
	b.ts_first_booking_created,
	b.ts_first_visit_completed,
	b.ts_first_tta_message_sent,
	b.ts_first_tta_attendance,
	b.ts_first_offer_sent,
	fm.dt_offer_accepted,
	fm.dt_ccv_signed,
	fm.dt_offer_rejected,											 
	fm.dt_payment_completed,
	b.nbr_bookings,
	b.nbr_visits_completed,
	b.nbr_tta_messages,
	b.nbr_tta_attendances,
	b.nbr_offers_sent,
	date_diff('day',b.ts_first_event, b.ts_first_offer_sent) as days_first_event_to_offer_sent,
	date_diff('day',b.ts_first_event, fm.dt_offer_accepted) as days_first_event_to_offer_accepted,
	date_diff('day',b.ts_first_event, fm.dt_ccv_signed) as days_first_event_to_ccv_signed,		 
	date_diff('day',b.ts_first_event, fm.dt_payment_completed) as days_first_event_to_payment_completed,
	date_diff('day',b.ts_first_offer_sent, fm.dt_offer_accepted) as days_offer_sent_to_offer_accepted,
	date_diff('day',b.ts_first_offer_sent, fm.dt_ccv_signed) as days_offer_sent_to_ccv_signed,
	date_diff('day',fm.dt_offer_accepted, fm.dt_ccv_signed) as days_offer_accepted_to_ccv_signed,	 
	date_diff('day',b.ts_first_offer_sent, fm.dt_payment_completed) as days_offer_sent_to_payment_completed,
	sk_first_event,
	sk_first_booking_created_date,
	sk_first_visit_completed_date,
	sk_first_tta_message_sent,
	sk_first_tta_attendance_date,
	sk_first_offer_sent_date,
	coalesce(sk_offer_accepted_date,-1) as sk_offer_accepted_date,
	coalesce(sk_offer_rejected_date,-1) as sk_offer_rejected_date,
	coalesce(sk_ccv_signed_date, -1) as sk_ccv_signed_date,							 
	coalesce(sk_payment_completed_date, -1) as sk_payment_completed_date,
	fm.flg_ccv_cancelled,
	offer_rejection_reason,
	offer_accepted_drop_reason,
	sale_listing_price,
	buyer_offer_price,
	offer_discount,
	sale_price_agreed,
	si.house_status_sale,
	si.house_status_reason_sale,
	si.house_status_rent,
	si.house_status_reason_rent,
	coalesce(mkt.app_type, '') as app_type,
	coalesce(mkt.utm_source, '') as utm_source,
	coalesce(mkt.utm_medium, '') as utm_medium,
	coalesce(mkt.utm_campaign, '') as utm_campaign,
	coalesce(mkt.flg_branded, False) as flg_branded,
	case
	    when (lower(mkt.utm_campaign) like '%sale%'
	        or lower(mkt.utm_campaign) like '%girafa%'
	        or lower(mkt.utm_campaign) like '%vender%'
	        or lower(mkt.utm_campaign) like 'whatsapp_s') then 'Sale'
	    when (lower(mkt.utm_campaign) is null
	        or lower(mkt.utm_campaign) = ''
	        or lower(mkt.utm_campaign) like '%branded%') then 'Organic'
	   else 'Rental'
	end as campaign_context,														 
	coalesce(mkt.mkt_category, 'Not Mapped') as mkt_category,
	coalesce(mkt.mkt_flow, 'Not Mapped') as mkt_flow,
	coalesce(mkt.mkt_completion, 'Not Mapped') as mkt_completion,
	coalesce(mkt.mkt_origin, 'Not Mapped') as mkt_origin,
	coalesce(mkt.mkt_channel, 'Not Mapped') as mkt_channel,
	coalesce(mkt.mkt_medium, 'Not Mapped') as mkt_medium,
	coalesce(mkt.mkt_source, 'Not Mapped') as mkt_source,
	coalesce(mkt.mkt_platform, 'Not Mapped') as mkt_platform														 
from sale_flows b
left join fix_monday fm
	on fm.sale_flow = b.sale_flow
left join buyer_offers bo 
	on bo.sale_flow = b.sale_flow
left join listings_status si 
	on si.id_house = b.id_house
left join sale_flow_taxonomy mkt
	on b.sale_flow = mkt.sale_flow
	and mkt.flow_order = 1
