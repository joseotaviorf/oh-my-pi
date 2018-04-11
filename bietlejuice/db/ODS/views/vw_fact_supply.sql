drop view public.vw_fact_supply;

create or replace view public.vw_fact_supply as
with base_doorman as (
	select
		"Status" as status,
		892700000 + "Cod Imóvel"::float::bigint as imovel_id
	from
		files.porteiros_legado
	where
		"Status" in ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead')
	and
		"Cod Imóvel" is not null
)
select
	f.id as ods_id,
	coalesce(f.lead_id, -1) as sk_lead,
	coalesce(f.conversao_id, -1) as sk_conversion,
	coalesce(f.photo_job_id, -1) as sk_photo_job,
	coalesce(f.imovel_id || '001' , '-1') as sk_property,
	coalesce(f.rep_id, -1) as sk_user_rep,
	coalesce(f.affiliate_id, -1) as sk_user_affiliate,
	coalesce(f.owner_id, -1) as sk_user_owner,
	coalesce(f.photographer_id, -1) as sk_user_photographer,
	coalesce(f.region_id, -1) as sk_region,
	coalesce(to_char(f.dt_lead::date,'YYYYMMDD')::integer, -1) as sk_lead_date,
	coalesce(to_char(f.dt_prospect::date,'YYYYMMDD')::integer, -1) as sk_prospect_date,
	coalesce(to_char(f.dt_qualified::date,'YYYYMMDD')::integer, -1) as sk_qualified_date,
	coalesce(to_char(f.dt_opportunity::date,'YYYYMMDD')::integer, -1) as sk_opportunity_date,
	coalesce(to_char(f.dt_first_listing::date,'YYYYMMDD')::integer, -1) as sk_first_listing_date,
	case
		when d.imovel_id is not null
		then 'Lead Flow'
		else f.flow
	end as flow,
	case
		when d.imovel_id is not null
		then 'Non-Self Service'
		else f.acquisition_method
	end as acquisition_method,
	case
		when d.imovel_id is not null
		then 'Doorman'
		else f.acquisition_channel
	end as acquisition_channel,
	f.lead_to_prospect_diff_minutes,
	f.prospect_to_qualified_diff_minutes,
	f.qualified_to_opportunity_diff_minutes,
	f.opportunity_to_listing_diff_minutes,
	f.lead_to_listing_diff_minutes
from
	fact_supply f
left join base_doorman d
	on f.imovel_id = d.imovel_id


