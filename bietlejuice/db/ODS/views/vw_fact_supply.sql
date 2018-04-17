drop view public.vw_fact_supply;

create or replace view public.vw_fact_supply as
with base_address as (
	select
		i.id,
		dense_rank() over (order by endereco, complemento, numero) as rn
	from
		imovel i
), row_merging as (
	select
		sup.id,
		sup.imovel_id,
		sup.dt_lead,
		sup.dt_prospect,
		sup.dt_qualified,
		sup.dt_opportunity,
		sup.dt_first_listing,
		coalesce(sup.dt_first_listing, sup.dt_opportunity, sup.dt_qualified, sup.dt_prospect, sup.dt_lead) as max_dt,
		coalesce(sup.dt_lead, sup.dt_prospect, sup.dt_qualified, sup.dt_opportunity, sup.dt_first_listing) as min_dt,
		case
			when sup.dt_first_listing is not null then 'listing'
			when sup.dt_opportunity is not null then 'opportunity'
			when sup.dt_qualified is not null then 'qualified'
			when sup.dt_prospect is not null then 'prospect'
			when sup.dt_lead is not null then 'lead'
		end as last_step,
		case
			when max(dt_first_listing) over (partition by base_address.rn) is not null
				then coalesce((dt_first_listing = max(dt_first_listing) over (partition by base_address.rn)), false)
			when max(dt_opportunity) over (partition by base_address.rn) is not null
				then coalesce((dt_opportunity = max(dt_opportunity) over (partition by base_address.rn)), false)
			when max(dt_qualified) over (partition by base_address.rn) is not null
				then coalesce((dt_qualified = max(dt_qualified) over (partition by base_address.rn)), false)
			when max(dt_prospect) over (partition by base_address.rn) is not null
				then coalesce((dt_prospect = max(dt_prospect) over (partition by base_address.rn)), false)
			when max(dt_lead) over (partition by base_address.rn) is not null
				then coalesce((dt_lead = max(dt_lead) over (partition by base_address.rn)), false)
			else true
		end as true_pl,
		base_address.rn,
		acquisition_channel,
		funnel_step
	from
		fact_supply sup
	left join
		base_address
		on base_address.id = sup.imovel_id
), reasons as (
	select
		m1.id,
		case
			when m1.acquisition_channel = 'Owner App' and m2.acquisition_channel <> 'Owner App'
			then 'AbandonedSelfService'
			when m1.last_step = 'qualified' and m2.id is not null then 'UnfinishedFlow'
			when m1.last_step = 'prospect' and m2.id is not null then 'UnfinishedForm'
			when m1.last_step = 'opportunity' then 'UnfinishedPhotoFlow'
			when m1.last_step = 'listing' then 'DuplicatedFlow'
			else null
		end as funnel_drop_reason
	from
		row_merging m1
	left join (select * from row_merging where true_pl = true) m2
		on m1.rn = m2.rn
		and m1.id <> m2.id
), base_supply as (
	select
		sup.*,
		r.funnel_drop_reason
	from
		fact_supply sup
	left join reasons r
	 on r.id = sup.id
), base_doorman as (
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
	coalesce(to_char(f.dt_first_inside_sales_contact::date,'YYYYMMDD')::integer, -1) as sk_first_inside_sales_contact_date,
	coalesce(to_char(f.dt_conversion::date,'YYYYMMDD')::integer, -1) as sk_conversion_date,
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
	f.funnel_step,
	f.funnel_drop_reason,
	f.lead_to_prospect_diff_minutes,
	f.prospect_to_qualified_diff_minutes,
	f.lead_to_first_inside_sales_contact_diff_minutes,
	f.prospect_to_first_inside_sales_contact_diff_minutes,
	f.qualified_to_opportunity_diff_minutes,
	f.opportunity_to_listing_diff_minutes,
	f.lead_to_listing_diff_minutes,
	f.lead_to_prospect_diff_hours,
	f.prospect_to_qualified_diff_hours,
	f.lead_to_first_inside_sales_contact_diff_hours,
	f.prospect_to_first_inside_sales_contact_diff_hours,
	f.qualified_to_opportunity_diff_hours,
	f.opportunity_to_listing_diff_hours,
	f.lead_to_listing_diff_hours,
	f.lead_to_prospect_diff_days,
	f.prospect_to_qualified_diff_days,
	f.lead_to_first_inside_sales_contact_diff_days,
	f.prospect_to_first_inside_sales_contact_diff_days,
	f.qualified_to_opportunity_diff_days,
	f.opportunity_to_listing_diff_days,
	f.lead_to_listing_diff_days
from
	base_supply f
left join base_doorman d
	on f.imovel_id = d.imovel_id


