-- filter only users that are tenants, thus have houses
with filter_owner_users as (
	select 
		u.id
	from datalake_ebdb_clean.user u
	inner join datalake_ebdb_clean.house h 
		on h.id_user = u.id
	group by 1
),
-- build owner tenant funnel from booking to contract considering house
user_to_contract as (
	select
		u.id,
		b.ts_created as ts_created_booking,
		b.status as status_booking,
		v.dt_visit,
		pp.ts_created as ts_created_pre_proposal,
		p.ts_created as ts_created_proposal,
		c.id as id_contract,
		c.ts_created as ts_created_contract,
		c.ts_signed as ts_signed_contract,
		c.status as status_contract
	from datalake_ebdb_clean.user u
	left join datalake_ebdb_clean.house h
		on u.id = h.id_user
	left join datalake_ebdb_clean.booking b
		on b.id_house = h.id
	left join datalake_ebdb_clean.visit v
		on v.id = b.id_visit
	left join datalake_ebdb_clean.rent_flow fl 
		on fl.id_house = h.id	
	left join datalake_ebdb_clean.pre_proposal pp
		on fl.id_house = pp.id_house	
	left join datalake_ebdb_clean.proposal p
		on p.id_pre_proposal = pp.id	
	left join datalake_ebdb_clean.contract c
		on c.id_proposal = p.id
),
-- get the timeline start from owner funnel
user_dates as (
	select
		id,
		cast(min(ts_created_booking) as date) as first_booking_date,
	    min(dt_visit) as first_visit_date,
		min(ts_created_pre_proposal) as first_pre_proposal_date,
		min(ts_created_proposal) as first_proposal_accepted_date,
		min(ts_created_contract) as first_contract_date,
		min(ts_signed_contract) as first_signed_contract
	from user_to_contract
	group by id
),
booking_metrics as (
	select
		u.id,
		count(b.id) as visits_booked,
		sum(case when b.visit_fup in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho') then 1 else 0 end) as visits_realized,
		sum(case when b.visit_fup is not null then 1 else 0 end) as visits_expected_to_happen
	from filter_owner_users u
	inner join datalake_ebdb_clean.house h 
		on u.id = h.id_user
	inner join datalake_ebdb_clean.booking b 
		on b.id_house = h.id
	group by u.id
),
contract_metrics as (
	select 
		id as id_user,
		count(case when status_contract in ('Ativo','Finalizado') then id_contract end) as contracts_signed,
		count(case when status_contract in ('Cancelado') then id_contract end) as contracts_cancelled,
		count(case when status_contract in ('Finalizado') then id_contract end) as contracts_annuled,
		count(case when status_contract in ('Minuta','PreAssinaturas') then id_contract end) as contracts_to_be_signed
	from user_to_contract
	group by 1
),
house_metrics as (
	select 
		id_user,
		count(id) as houses_registered,
		count(case when is_for_rent = true then id end) as houses_registered_for_rent,
		count(case when is_for_sale = true then id end) as houses_registered_for_sale
	from datalake_ebdb_clean.house
	group by id_user
),
-- build offer ETL from both sources (old and Firestore) to create offer metrics
old_pre_proposal as (
	select
		id as id_offer,
		(id * 100) + 1 as sk_offer,
		status,
		id_user as user_id,
		id_house as house_id,
		cast(ts_created as date) as dt_created,
		cast(ts_updated as date) as dt_updated,
		cast(ts_last_edition_updated as date) as offer_submitted,
		rejection_reason
	from datalake_ebdb_clean.pre_proposal
),
offer_firestore as (
	select
		eo.id as id_offer,
		max(coalesce(eo.id_godfather, go_firestore.id)) over (partition by eo.id_firestore) as godfatherid
    from datalake_ebdb_clean.offer eo
    left join datalake_godfather_clean.offer go_firestore
		on eo.id_firestore = go_firestore.id_firestore
        and eo.id_godfather is null
),
firestore_offers as (
	select
		offer_firestore.id_offer,
		go_firestore.id_firestore,
		go_firestore.id,
		go_firestore.ts_first_sent,
		go_firestore.ts_last_sent,
		go_firestore.type as distinct_type
	from offer_firestore
	join datalake_godfather_clean.offer go_firestore
    	on go_firestore.id = godfatherid
	group by 1,2,3,4,5,6
),
new_offer as (
	select
		distinct o.id as id_offer,
		(o.id * 100) + 2 as sk_offer,
		o.status,
		o.id_client as user_id,
		o.id_house,
		cast(o.ts_created as date) as dt_created,
		cast(o.ts_updated as date) as dt_updated,
		coalesce(go_godfather.ts_last_sent, go_firestore.ts_last_sent) as offer_submitted,
		o.rejection_reason
	from datalake_ebdb_clean.offer o 
	left join datalake_godfather_clean.offer go_godfather
		on o.id_godfather = go_godfather.id
    	and o.id_godfather is not null
	left join firestore_offers go_firestore
  		on o.id = go_firestore.id_offer
),
all_offers as (
	select * from new_offer
	union
	select * from old_pre_proposal
),
offer_metrics as (
	select 
		u.id,
		min(o.offer_submitted) as first_offer_sent_date,
		count(o.id_offer) as offers_sent,
		count(case when o.status = 'Aprovada' then o.id_offer end) as offers_approved,
		count(case when o.status = 'Rejeitada' then o.id_offer end) as offers_rejected,
		count(case when o.status = 'EmNegociacao' then o.id_offer end) as offers_negotiating
	from filter_owner_users u 
	inner join datalake_ebdb_clean.house h 
		on u.id = h.id_user
	inner join all_offers o 
		on o.id_house = h.id
	group by 1
),
contract_owner as (
	select 
		c.id as sk_contract,
		coalesce(h.id_user, pa_b2b_online.id_user,pa_b2b_prime.id_user, -1) as sk_owner
	from datalake_ebdb_clean.contract c
	join datalake_ebdb_clean.house h
		on c.id_house = h.id
	left join datalake_ebdb_clean.partner_agent pa_b2b_prime
		on h.id_user = pa_b2b_prime.id_user
	left join datalake_ebdb_clean.conversion_lead lc
		on lc.id_house = h.id
	left join datalake_ebdb_clean.lead l
		on l.id = lc.id_converted_lead
	    and l.affiliate_type = 'B2BPartner'
	left join datalake_ebdb_clean.partner_agent pa_b2b_online
	  on pa_b2b_online.id_user = l.id_agent_has_indicated
),
-- build rule for ongoing contracts such as described in Strategy datamart
ongoing_contracts as ( 
	select 
		id,
		case when status in ('Ativo','Finalizado') 
			and type <> 'DealOnly'
			and current_date >= date(coalesce(coalesce(ts_signed,dt_started),dt_entered))
			and (current_date < dt_termination or dt_termination is null)
			then true
		else false end as is_ongoing_contract
	from datalake_ebdb_clean.contract
),
-- identify owners that have ongoing contracts
owner_ongoing as (
	select 
		co.sk_owner,
		count(sk_contract) > 0 as has_ongoing_contract
	from contract_owner co 
	inner join ongoing_contracts oc 
		on co.sk_contract = oc.id
		and is_ongoing_contract = true
	group by 1
),
-- build listing ETL considering versioning model to create listing metrics from version 0
listing_etl as (
	with house_aud as (
	    select
		  from_unixtime(rev.ts_revision)/1000 as revision_time, -- datetime status started
		  cast(from_unixtime(rev.ts_revision/1000) as date) as status_date, -- date status started
		  rev.id_user, -- user responsible to change status
		  rev.reason, -- reason status changed
		  lag(i.status) over(partition by i.id_house order by i.rev) as previous_status, -- previous status ordered by the datetime that happened
		  lag(i.rent) over(partition by i.id_house order by i.rev) as previous_rent_price,
		  i.* -- all information from Imovel table
	    from datalake_ebdb_clean.house_aud i
		inner join datalake_ebdb_clean.user_revision_entity rev
		  on rev.id = i.rev
	),
	house_status_history as (
	select
		id_house,
		rev,
		mod_status,
		max(dt_first_publication) over(partition by id_house) as ts_first_publication,
		revision_time as ts_status_changed,
		status as status_history,
		lead(revision_time) over(partition by id_house order by rev) as next_status_change_time,
		-- last_value(status) over(partition by id rows between unbounded preceding and unbounded following) as current_status,
		row_number() over(partition by id_house order by rev) as order_status
	from house_aud 
	where (status <> previous_status or previous_status is null)
	),
	house_new_status_new_date as (
	select
		*,
		case when status_history = 'despublicado' then datediff(cast(ts_status_changed as timestamp),coalesce(cast(next_status_change_time as timestamp),now())) end as days_unpublished,
		case when status_history is null then 'publicado' else status_history end as new_status_history,
	    case when status_history is null then ts_first_publication else cast(ts_status_changed as timestamp) end as new_ts_status_changed,
	    max(order_status) over(partition by id_house) as max_order_status
	from house_status_history
	),
	house_status_version_changes as (
	select
		*,
		case when new_status_history = 'alugado' or
		          (new_status_history = 'despublicado' and days_unpublished >= 84) then 1
	         else 0 end as events_change_version,
		case when new_status_history = 'alugado' or
		          (new_status_history = 'despublicado' and days_unpublished >= 84) then new_status_history
		     end as events_change_status,
		sum(case when new_status_history = 'alugado' or
		              (new_status_history = 'despublicado' and days_unpublished >= 84) then 1
	             else 0 end) over (partition by id_house order by rev rows unbounded preceding) as sum_events_change_version
	from house_new_status_new_date h_new
	),
	house_status_version_first_publi as (
	select
		*,
		min(case when new_status_history = 'publicado' then new_ts_status_changed
		         end) over(partition by id_house, sum_events_change_version order by rev) as first_publication_change_version
	from house_status_version_changes
	),
	house_status_version_publications as (
	select
		*,
		max(first_publication_change_version) over (partition by id_house order by rev rows unbounded preceding) as publication_version_date
	from house_status_version_first_publi
	),
	house_status_version_order as (
	select
		*,
		case when publication_version_date is null then 0 else dense_rank() over(partition by id_house order by publication_version_date) end as order_version
	from house_status_version_publications
	),
	max_status_order as (
		select
			id_house,
			order_version,
			max(order_status) as max_order_status
		from house_status_version_order
		group by id_house, order_version
	),
	house_status_version_last_status as (
		select
		   hs_vo.*,
		   max(
		     case
		       when hs_vo.new_status_history = 'despublicado'
		         then new_ts_status_changed
		     end
		   ) over(partition by hs_vo.id_house, hs_vo.order_version) as ts_last_de_publication,
		   case when ms_o.max_order_status is not null then hs_vo.new_status_history end as last_status,
		   max(hs_vo.order_status) over(partition by hs_vo.id_house, hs_vo.order_version) as max_order_status_version
	    from house_status_version_order hs_vo
	    left join max_status_order ms_o
	      on hs_vo.id_house = ms_o.id_house
	      and hs_vo.order_version = ms_o.order_version
	      and hs_vo.order_status = ms_o.max_order_status
	),
	status_change_version as (
	select
		id_house,
		order_version,
		max(events_change_status) as category_change
	from house_status_version_last_status
	where events_change_status is not null
	group by 1, 2
	),
	house_listing_plain as (
	select
		hs_v.id_house,
		hs_v.order_version as version,
		sc_v.category_change as change_version_status,
		hs_v.ts_last_de_publication,
		max(status_history) as status_history,
		max(ts_status_changed) as ts_status_changed,
		max(hs_v.last_status) as status,
		min(cast(hs_v.publication_version_date as timestamp)) as ts_listing_version_start,
		max(coalesce(cast(hs_v.next_status_change_time as timestamp),cast('2200-01-01 12:00:00' as timestamp))) as ts_listing_version_end
	from house_status_version_last_status hs_v
	left join status_change_version sc_v
	  on hs_v.id_house = sc_v.id_house
	  and hs_v.order_version = sc_v.order_version
	group by 1, 2, 3, 4
	),
	house_listing_full as (
	select
		cast(cast(id_house as string)||'00'||cast(version as string) as bigint) as id_house_listing,
		id_house,
		version,
		case when version = 0 then null
		     when version = 1 then 'First Listing'
		     when version <> 0 and lag(change_version_status) over(partition by id_house order by version) = 'alugado' then 'Re-Listing'
		     when version <> 0 and lag(change_version_status) over(partition by id_house order by version) in ('despublicado') then 'Recovered'
		     else null end as listing_category_start,
		status,
		status_history,
		ts_status_changed,
		ts_listing_version_start,
		nullif(cast(ts_listing_version_end as timestamp),cast('2200-01-01 12:00:00' as timestamp)) as ts_listing_version_end,
		ts_last_de_publication
	from house_listing_plain
	)
	select * from house_listing_full
),
-- get all listings from each corresponding owner
listing_owner as (
	select 
		h.id_user,
		h.id,
		h.is_for_rent,
		h.is_for_sale,
		l.id_house_listing,
		l.ts_listing_version_start,
		l.status
	from datalake_ebdb_clean.house h
	left join listing_etl l 
		on h.id = l.id_house
),
listing_metrics as (
	select 
		id_user,
		min(ts_listing_version_start) as first_listing_date,
		count(id_house_listing) as listings_registered,
		count(case when is_for_rent = true then id_house_listing end) as listings_registered_for_rent,
		count(case when is_for_sale = true then id_house_listing end) as listings_registered_for_sale,
		count(case when status = 'publicado' then id_house_listing end) as active_listings,
		count(case when status = 'publicado' and is_for_rent = true then id_house_listing end) as active_listings_for_rent,
		count(case when status = 'publicado' and is_for_sale = true then id_house_listing end) as active_listings_for_sale
	from listing_owner
	group by 1
)
select
	u.id as sk_user,
	coalesce(cast(date_format(lm.first_listing_date, 'yyyyMMdd') as integer), -1) as sk_first_listing_date,
	coalesce(cast(date_format(ud.first_booking_date, 'yyyyMMdd') as integer), -1) as sk_first_booking_date,
	coalesce(cast(date_format(ud.first_visit_date, 'yyyyMMdd') as integer), -1) as sk_first_visit_date,
	coalesce(cast(date_format(om.first_offer_sent_date, 'yyyyMMdd') as integer), -1) as sk_first_offer_received_date,
	coalesce(cast(date_format(ud.first_proposal_accepted_date, 'yyyyMMdd') as integer), -1) as sk_first_proposal_accepted_date,
	coalesce(cast(date_format(ud.first_signed_contract, 'yyyyMMdd') as integer), -1) as sk_first_contract_signed_date,
	coalesce(hm.houses_registered,0) as houses_registered,
	coalesce(hm.houses_registered_for_rent,0) as houses_registered_for_rent,
	coalesce(hm.houses_registered_for_sale,0) as houses_registered_for_sale,
	coalesce(lm.listings_registered,0) as listings_registered,
	coalesce(lm.listings_registered_for_rent,0) as listings_registered_for_rent,
	coalesce(lm.listings_registered_for_sale,0) as listings_registered_for_sale,
	coalesce(bm.visits_booked,0) as visits_booked,
	coalesce(bm.visits_realized,0) as visits_realized,
	coalesce(bm.visits_expected_to_happen,0) as visits_expected_to_happen,
	coalesce(om.offers_sent,0) as offers_received,
	coalesce(om.offers_approved,0) as offers_approved,
	coalesce(om.offers_rejected,0) as offers_rejected,
	coalesce(om.offers_negotiating,0) as offers_negotiating,
	coalesce(cm.contracts_signed,0) as contracts_signed,
	coalesce(cm.contracts_cancelled,0) as contracts_cancelled,
	coalesce(cm.contracts_annuled,0) as contracts_annuled,
	coalesce(cm.contracts_to_be_signed,0) as contracts_to_be_signed,
	coalesce(lm.active_listings > 0, false) as has_active_listings,
	coalesce(lm.active_listings_for_rent > 0, false) as has_active_listings_for_rent,
	coalesce(lm.active_listings_for_sale > 0, false) as has_active_listings_for_sale,
	coalesce(bm.visits_expected_to_happen > 0,false) as has_visits_to_happen,
	coalesce(om.offers_negotiating > 0,false) as is_negotiating_offers,
	coalesce(cm.contracts_to_be_signed > 0,false) as has_contracts_to_sign,
	coalesce(oo.has_ongoing_contract, false) as has_ongoing_contracts,
    now() as ts_load
from filter_owner_users u
inner join user_dates ud 
	on ud.id = u.id
left join listing_metrics lm 
	on lm.id_user = u.id
inner join house_metrics hm 
	on hm.id_user = u.id
left join booking_metrics bm 
	on bm.id = u.id
left join offer_metrics om 
	on om.id = u.id
left join contract_metrics cm 
	on cm.id_user = u.id
left join owner_ongoing oo
	on oo.sk_owner = u.id
