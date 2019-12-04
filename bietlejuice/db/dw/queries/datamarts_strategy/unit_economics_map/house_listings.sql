-- Table with listing general information

with 
amenidades as (
-- Include amenities from product property table
	select 
	 distinct
		i.imovel_id,
		a.id,
		a.nome
	from datalake_ebdb_raw_prod.imovel_amenidades i 
	left join datalake_ebdb_raw_prod.amenidadesinfo ai 
	  on ai.imovel_id = i.imovel_id 
	left join datalake_ebdb_raw_prod.amenidades a 
	  on ai.amenidades_id = a.id 
	where ai.temCaracteristica and a.id = 13
),
info_imovel as (
-- Include information from product property table
	select 
		im.id as imovel_id, 
		im.aptosporandar as units_by_floor,
		im.shorturl,
		im.estadoconservacao, 
		im.andarespredio as total_floors,
		im.descricaoimovel as house_description,
		im.andar as house_floor,
		im.estacaomaisproxima_id as closest_station,
		loc.nome as closest_station_name,
		im_a.nome is not null as accept_pets 
	from datalake_ebdb_raw_prod.imovel im
	left join datalake_ebdb_raw_prod.local loc
	  on im.estacaomaisproxima_id = loc.id and loc.active
	left join amenidades im_a
	  on im.id = im_a.imovel_id
),
rent_flows_count as (
-- Count of events related to rent flows and first 
select 
	sk_house_listing,
	min(case when sk_booking_created_date > 0 then sk_booking_created_date end) as first_booking_date,
	min(case when sk_booking_created_date > 0 and sk_contract_signed_date > 0 then sk_booking_created_date end) as first_booking_contract_date,
	min(case when sk_offer_approved_date > 0 then sk_offer_approved_date end) as first_offer_approved_date,
	min(case when sk_offer_approved_date > 0 and sk_contract_signed_date > 0 then sk_offer_approved_date end) as first_offer_approved_contract_date,
	min(case when sk_credit_analysis_end_date > 0 then sk_credit_analysis_end_date end) as first_credit_analysis_processed_date,
	min(case when sk_credit_analysis_end_date > 0 and sk_contract_signed_date > 0 then sk_credit_analysis_end_date end) as first_credit_analysis_processed_contract_date,
	min(case when sk_contract_created_date > 0 then sk_contract_created_date end) as first_contract_created_date,
	min(case when sk_contract_created_date > 0 and sk_contract_signed_date > 0 then sk_contract_created_date end) as first_contract_created_contract_date,
	count(distinct case when sk_booking_created_date > 0 then sk_booking end) as total_bookings,
	count(distinct case when sk_visit_date > 0 and flg_visit_completed is true then sk_visit end) as total_visits_completed,
	count(distinct case when sk_offer_submitted_date > 0 then sk_offer end) as total_offers_submitted,
	count(distinct case when sk_offer_approved_date > 0 then sk_offer end) as total_offers_approved,
	count(distinct case when sk_contract_created_date > 0 and sk_contract_canceled_date > 0 then sk_contract end) as total_contracts_canceled
from fact_listing_rent_flows
group by 1
),
house_listing_info as (
select
	distinct
-- Listing identification	
	dhl.sk_house_listing,
	dhl.id_house,
	dhl.status as listing_current_status,
	dhl.listing_category_start,
	dhl.is_exclusive,
	dhl.is_originals_active,
	info_im.shorturl,
	lf.mkt_origin,
	lf.mkt_completion,

	
-- Listing localization
    dr.sk_region,
	dr.regional,
	dr.city_group,
	dr.city_name,
	dr.name as neighborhood,
	
-- Listing b2b identification	
	dhl.is_b2b,
	dp.trade_name as partner_name,
	
-- Listing general attributes 	
	dhl.rent as house_listing_rent_price_published,
	dhl.house_rent as house_rent_price_published,
	dhl.house_predicted_price,
	dhl.house_condo,
	dhl.house_iptu,
	dhl.house_total_value,
	dhl.is_house_furnished as has_furniture,
	dhl.house_elevator as has_elevator,
	dhl.house_bathrooms,
	dhl.house_bedrooms,
	dhl.house_suites,
	dhl.house_total_area,
	dhl.house_garages,
	dhl.house_garage_type,
	dhl.house_type,
	dhl.house_entrance,
	dhl.key_type,
	info_im.units_by_floor,
	info_im.total_floors,
	info_im.house_description as house_site_description, 
	info_im.house_floor,
	info_im.closest_station_name,
	info_im.accept_pets,

-- Listing dates
	lf.sk_prospect_date,	
	dhl.ts_listing_version_start,
	dhl.ts_listing_version_end,
	rfc.first_booking_date,
	rfc.first_booking_contract_date,
	rfc.first_offer_approved_date,
	rfc.first_offer_approved_contract_date,
	rfc.first_credit_analysis_processed_date,
	rfc.first_credit_analysis_processed_contract_date,
	date(nullif(rf.sk_credit_analysis_approved_date,-1)) as credit_analysis_approved_date,
	rfc.first_contract_created_date,
	rfc.first_contract_created_contract_date,
    date(nullif(rf.sk_contract_signed_date,-1)) as contract_signed_date,	
	dc.dt_start,
	dc.dt_entrance,
	date(nullif(rf.sk_contract_annulment_date,-1)) as contract_annulment_date,
    case when dhl.status = 'despublicado' and rf.sk_contract is null then datediff(day,dhl.ts_listing_version_start,dhl.ts_last_de_publication)
         when rf.sk_contract is not null then datediff(day,dhl.ts_listing_version_start,dc.dt_start) 
         end as days_between_listing_and_unpublished_or_rental_start,
	rf.days_house_listing_to_contract_signed as days_between_listing_and_contract_signed,
	case when coalesce(dc.dt_start,dc.dt_entrance) is null then NULL 
		else datediff(day,coalesce(dc.dt_start,dc.dt_entrance),coalesce(dc.dt_annulment,current_date)) 
    	end as days_between_rental_start_and_contract_annulment,
	datediff(day,dhl.ts_listing_version_start,current_date - interval '1 day') as days_between_listing_and_current_date,
	
--Information about contract	
	rf.sk_contract,
	dc.status as contract_status,
	dc.rent as house_listing_rent_price_contract,
	
--Quantities
	rfc.total_bookings,
	rfc.total_visits_completed,
	rfc.total_offers_submitted,
	rfc.total_offers_approved,
	rfc.total_contracts_canceled	
	
from dim_house_listing dhl
left join fact_house_listing_flows lf
  on dhl.id_house = substring(lf.sk_house_listing,1,9) and lf.sk_first_listing_date > 0
left join dim_partner dp
  on lf.sk_partner = dp.sk_partner	
left join fact_listing_rent_flows rf
  on dhl.sk_house_listing = rf.sk_house_listing and sk_contract_signed_date > 0
left join dim_region dr
  on lf.sk_region = dr.sk_region
left join dim_contract dc
  on rf.sk_contract = dc.sk_contract  
left join info_imovel info_im   
  on info_im.imovel_id = dhl.id_house
left join rent_flows_count rfc
  on dhl.sk_house_listing = rfc.sk_house_listing
where dhl.version > 0 and dhl.ts_house_first_publication >= '2016-01-01'
order by 1
-- about 132k listings, 106k since 2018
)
select 
	* 
from house_listing_info