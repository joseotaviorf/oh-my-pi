-- A Sale Flow is defined by the tuple buyer <> house . It can start with three possible events (BOOKING, TALK TO AGENT OR DIRECT OFFER) -- 
-- Bookings and visits - first dates and counts
with booking as (
	select
		a.id_visitor||'_'||a.id_property as sale_flow, 
		cast(a.id_visitor as integer) as id_user,
		cast(a.id_property as integer) as id_house,
		min(date_parse(nullif(a.dt_created, ''), '%Y-%m-%d %H:%i:%s')) as ts_first_booking_created,
		min(case when status = 'Realizado' then date_parse(nullif(a.dt_scheduling, ''), '%Y-%m-%d %H:%i:%s') end) as ts_first_visit_completed,
		count(distinct a.id_booking) as nbr_bookings,
		count(distinct case when status = 'Realizado' then a.id_booking end) as nbr_visits_completed
	from datalake_clean.ods_dim_booking a
	where
		a.visit_intent = 'SALE'
		and a.type = 'Visita'
	group by 1, 2, 3
)
-- Talk to agent messages sent and attendances - first dates and counts
, tta_messages as (
	select 
		id_user||'_'||json_extract_scalar(event_properties, '$.house_id') as sale_flow,
		cast(json_extract_scalar(event_properties, '$.house_id') as integer) as id_house,
		cast(id_user as integer) as id_user,
		cast(json_extract_scalar(event_properties, '$.agent_id') as integer) as id_agent,
		cast(evt.ts_event as timestamp) as ts_message_sent
	from datalake_amplitude_clean_prod.events evt
	where 
		event_type = 'piloto_cw_message_sent'
		and ts_event > timestamp '2020-03-01 00:00' --month_start of tta event
		and evt.id_app = 170698
	)
, sale_tta_messages as (
	select
		tta.sale_flow,
		tta.id_house,
		tta.id_user,
		min(ts_message_sent) as ts_first_tta_message_sent,
		count(ts_message_sent) as nbr_tta_messages
	from tta_messages tta
	join datalake_clean.ods_dim_user sa
		on tta.id_agent = cast(sa.id as integer) 
		and sa.is_sale_agent = 'True'
	join datalake_ebdb_clean_prod.listing_business_context lbc 
		on lbc.id_house = tta.id_house
	where 
		tta.sale_flow is not null 
		and lbc.business_context = 'SALE'
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
, offer_amplitude as (
	select
		id_user||'_'||json_extract_scalar(event_properties, '$.house_id') as sale_flow,
		cast(trim(json_extract_scalar(event_properties, '$.offer_id')) as varchar) as id_offer,
		cast(trim(json_extract_scalar(evt.event_properties, '$.house_id')) as integer) as id_house,
		cast(evt.id_user as integer) as id_user,
		cast(evt.ts_event as timestamp) as ts_offer_sent
	from datalake_amplitude_clean_prod.events evt
	where 
		evt.event_type = 'sale_offer_form_accepted'
		and evt.id_app = 170698
)
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
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_proposta,''), 1, 10), '-', '') as integer),-1) as sk_offer_sent_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_aceite_proposta, ''), 1, 10), '-', '') as integer),-1) as sk_offer_accepted_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_assinatura_ccv, ''), 1, 10), '-', '') as integer),-1) as sk_ccv_signed_date,
		coalesce(CAST(REPLACE(SUBSTRING(nullif(mo.data_descarte, ''), 1, 10), '-', '') as integer),-1) as sk_offer_rejected_date,
		motivo_descarte_pre as offer_rejection_reason,
		motivo_descarte_pos as offer_accepted_drop_reason,
		status_proposta,
		cast(nullif(mo.valor_anuncio, '') as integer) as sale_listing_price,
		cast(nullif(mo.proposta_buyer, '') as integer) as buyer_offer_price,
		case when mo.valor_anuncio ='' or mo.proposta_buyer ='' then null else (cast(mo.valor_anuncio as decimal) - cast(mo.proposta_buyer as decimal))*1.00/cast(mo.valor_anuncio as decimal) end as offer_discount
	from datalake_raw.gsheets_sale_offers_monday mo  
)
-- Remove duplicates (invalid offers) from Monday gsheets (only 16 cases)
, fix_monday as (
	select 
	    tm.sale_flow,
	    tm.id_house,
	    tm.id_user,
	    max(tm.dt_offer_accepted) as dt_offer_accepted,
	    max(tm.dt_offer_rejected) as dt_offer_rejected,
	    max(tm.dt_ccv_signed) as dt_ccv_signed,
	    max(tm.sk_offer_accepted_date) as sk_offer_accepted_date,
	    max(tm.sk_offer_rejected_date) as sk_offer_rejected_date,
	    max(tm.sk_ccv_signed_date) as sk_ccv_signed_date,
	    max(tm.offer_rejection_reason) as offer_rejection_reason,
	    max(tm.offer_accepted_drop_reason) as offer_accepted_drop_reason,
	    max(tm.sale_listing_price) as sale_listing_price,
	    max(tm.buyer_offer_price) as buyer_offer_price,
	    max(tm.offer_discount) as offer_discount
	from treat_monday tm
	group by 1, 2, 3
)
-- First We search the offer data from amplitude (less errors with id_users/nulls). Otherwise if there's an id_offer only present in Monday we bring monday data
, offer_sent as (
	select
		cast(coalesce(o.id_user, fm.id_user) as varchar)||'_'||cast(coalesce(o.id_house, fm.id_house) as varchar) as sale_flow,
		coalesce(o.id_house, fm.id_house) as id_house,
		coalesce(o.id_user, fm.id_user) as id_user,
		coalesce(min(o.ts_offer_sent),min(fm.dt_offer_sent)) as ts_first_offer_sent,
		count(distinct coalesce(o.id_offer, fm.id_offer)) as nbr_offers_sent
	from offer_amplitude o
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
		row_number() over (partition by os.id_user order by ts_first_offer_sent) as rw_offer_sent
	from offer_sent os
)
, sellers_info as (
	select 
		h.id_user as id_seller,
		h.id as id_house
	from datalake_ebdb_clean_prod.house h
	join datalake_ebdb_clean_prod.listing_business_context lbc 
		on lbc.id_house = h.id 
	where
		lbc.business_context = 'SALE'
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
		row_number() over (partition by coalesce(b.id_user, o.id_user, tta.id_user) order by least(coalesce(b.ts_first_booking_created,timestamp '2030-01-01'), coalesce(o.ts_first_offer_sent,timestamp '2030-01-01'), coalesce(tta.ts_first_tta_message_sent,timestamp '2030-01-01'))) as rw_sale_flow
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
		when b.rw_sale_flow = 1 then true
		else false
	end as is_buyer_first_sale_flow,
	case 
		when bo.rw_offer_sent = 1 then true
		else false
	end as is_buyer_first_offer,
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
	b.nbr_bookings,
	b.nbr_visits_completed,
	b.nbr_tta_messages,
	b.nbr_tta_attendances,
	b.nbr_offers_sent,
	date_diff('day',b.ts_first_event, b.ts_first_offer_sent) as days_first_event_to_offer_sent,
	date_diff('day',b.ts_first_event, fm.dt_offer_accepted) as days_first_event_to_offer_accepted,
	date_diff('day',b.ts_first_event, fm.dt_ccv_signed) as days_first_event_to_ccv_signed,
	date_diff('day',b.ts_first_offer_sent, fm.dt_offer_accepted) as days_offer_sent_to_offer_accepted,
	date_diff('day',b.ts_first_offer_sent, fm.dt_ccv_signed) as days_offer_sent_to_ccv_signed,
	date_diff('day',fm.dt_offer_accepted, fm.dt_ccv_signed) as days_offer_accepted_to_ccv_signed,
	sk_first_event,
	sk_first_booking_created_date,
	sk_first_visit_completed_date,
	sk_first_tta_message_sent,
	sk_first_tta_attendance_date,
	sk_first_offer_sent_date,
	coalesce(sk_offer_accepted_date,-1) as sk_offer_accepted_date,
	coalesce(sk_offer_rejected_date,-1) as sk_offer_rejected_date,
	coalesce(sk_ccv_signed_date, -1) as sk_ccv_signed_date,
	offer_rejection_reason,
	offer_accepted_drop_reason,
	sale_listing_price,
	buyer_offer_price,
	offer_discount
from sale_flows b
left join fix_monday fm
	on fm.sale_flow = b.sale_flow
left join buyer_offers bo 
	on bo.sale_flow = b.sale_flow
left join sellers_info si 
	on si.id_house = b.id_house
