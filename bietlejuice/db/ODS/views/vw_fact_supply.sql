drop view public.vw_fact_supply;

create or replace view public.vw_fact_supply as
with legacy_doorman as (
	select
		"Status" as status,
		892700000 + "Cod Imóvel"::float::bigint as imovel_id
	from
		files.porteiros_legado
	where
		"Status" in ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead')
	and
		"Cod Imóvel" is not null
),
base_tasks as (
	select
		*,
		row_number() over (partition by lead_id order by dt_created desc) as rn
	from
		crm.lead_tasks
),
base_leads as (
	select
		id as lead_id,
		tipo as lead_type,
		origem as lead_origin,
		utm_source,
		utm_medium,
		coalesce((lower(trim(utm_campaign))  ~* '(institucional)|(branded)'), false) as branded_lead,
		codigo_imobiliaria is not null as b2b_lead,
		case
			when origem='Reprocessado' then reprocessed_lead_id
			else null
		end as old_lead_id
	from
		lead
), -- reprocessed leads being merged to their original ones
rep_leads as (
	select
		bl.lead_id,
		bl.lead_type,
		bl.lead_origin,
		coalesce(old_bl.utm_source, bl.utm_source) as utm_source,
		coalesce(old_bl.utm_medium, bl.utm_medium) as utm_medium,
		coalesce(old_bl.branded_lead, bl.branded_lead) as branded_lead,
		coalesce(old_bl.b2b_lead, bl.b2b_lead) as b2b_lead
	from
		base_leads bl
	left join
		base_leads old_bl
		on old_bl.lead_id = bl.old_lead_id
),
potential_listings as (
	select
		f.id as ods_id,
		coalesce(f.lead_id, -1) as sk_lead,
		coalesce(f.conversao_id, -1) as sk_conversion,
		coalesce(f.photo_job_id, -1) as sk_photo_job,
		coalesce(f.imovel_id || '001' , '-1') as sk_property,
		coalesce(f.rep_id, -1) as sk_user_rep,
		coalesce(f.rep_id, bt.rep_id, -1) as sk_user_sales_rep,
		coalesce(f.affiliate_id, -1) as sk_user_affiliate,
		coalesce(bt.rep_id, -1) as sk_user_task_assignee,
		coalesce(f.owner_id, -1) as sk_user_owner,
		coalesce(f.photographer_id, -1) as sk_user_photographer,
		coalesce(f.region_id, -1) as sk_region,
		coalesce(to_char(f.dt_lead::date,'YYYYMMDD')::integer, -1) as sk_lead_date,
		coalesce(to_char(f.dt_prospect::date,'YYYYMMDD')::integer, -1) as sk_prospect_date,
		coalesce(to_char(bt.dt_created::date, 'YYYYMMDD')::integer, -1) as sk_task_created_date,
		coalesce(to_char(f.dt_first_inside_sales_contact::date,'YYYYMMDD')::integer, -1) as sk_first_inside_sales_contact_date,
		coalesce(to_char(f.dt_conversion::date,'YYYYMMDD')::integer, -1) as sk_conversion_date,
		coalesce(to_char(f.dt_qualified::date,'YYYYMMDD')::integer, -1) as sk_qualified_date,
		coalesce(to_char(f.dt_opportunity::date,'YYYYMMDD')::integer, -1) as sk_opportunity_date,
		coalesce(to_char(f.dt_first_listing::date,'YYYYMMDD')::integer, -1) as sk_first_listing_date,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then 'Lead Flow'
			else f.flow
		end as flow,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then 'Non-Self Service'
			else f.acquisition_method
		end as acquisition_method,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then 'Doorman'
			else f.acquisition_channel
		end as acquisition_channel,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then 'Doorman'
			else f.acquisition_source
		end as acquisition_source,
		case
			when f.dt_first_listing is not null then 'listing'
			when f.dt_opportunity is not null then 'opportunity'
			when f.dt_qualified is not null then 'qualified'
			when f.dt_prospect is not null then 'prospect'
			when f.dt_lead is not null then 'lead'
		end::varchar(255) as funnel_step,
		f.funnel_step as funnel_drop_reason,
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
		f.lead_to_listing_diff_days,
		f.exclusivity,
		bl.lead_type,
		bl.lead_origin,
		bl.utm_source,
		bl.utm_medium,
		bl.branded_lead,
		bl.b2b_lead,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then true
			else (f.acquisition_source = 'Doorman')
		end as doorman_lead,
		(acquisition_channel = 'Inside Sales') as isales_direct_register,
		(acquisition_channel = 'Admin') as cx_direct_register,
		(bt.rep_id is not null) as isales_intervention
	from
		fact_supply f
	left join
		legacy_doorman d
		on f.imovel_id = d.imovel_id
	left join
		base_tasks bt
		on bt.lead_id = f.lead_id
		and bt.rn = 1
	left join
		rep_leads bl
		on bl.lead_id = f.lead_id
), -- initial categories that will derivate others
initial_categories as (
	select
		*,
		case
			when lead_origin = 'Reprocessado' then 'Outbound'
			when b2b_lead then 'Outbound'
			when doorman_lead then 'Outbound'
			when lead_origin = 'Crawling' then 'Outbound'
			when lead_type = 'Afiliado' then 'Outbound'
			when acquisition_method = 'Self-Service' then 'Inbound'
			when lead_type in ('Marketing', 'OpenLink', 'BrokenOpenLink') then 'Inbound'
			else 'Other'
		end as mkt_category,
		case
			when lead_type in ('Proporparceria', 'CadastroImobiliario') then 'Other'
			else acquisition_method
		end as mkt_flow,
		case
			when branded_lead then 'Branded'
			else 'Other'
		end as mkt_branded,
		case
			when lead_origin = 'Reprocessado' then 'Reprocessed'
			when lead_type in ('Afiliado', 'OpenLink', 'LandingOpenLink') then 'Affiliates'
			when b2b_lead or doorman_lead then 'Affiliates'
			when lead_origin = 'Crawling' then 'Other'
			when isales_direct_register or cx_direct_register then 'Other'
			else 'Online'
		end as mkt_channel_type
	from potential_listings
), -- remaining categories
final_categories as (
	select
		*,
		case
			when mkt_flow in ('Non-Self Service', 'Other') then mkt_flow
			when isales_intervention and mkt_flow = 'Self-Service' then 'Recovered Self-Service'
			when mkt_flow = 'Self-Service'  then 'Full Self-Service'
			else 'Other'
		end as mkt_completion,
		case
			when mkt_channel_type = 'Reprocessed' then 'Reprocessed'
			when doorman_lead then 'Doorman'
			when b2b_lead then 'B2B'
			when isales_direct_register then 'Inside Sales'
			when cx_direct_register then 'CX'
			when mkt_channel_type = 'Affiliates' then 'IndicaAi'
			when lead_origin = 'Crawling' then 'Crawling'
			when branded_lead then 'Online Free'
			when utm_source = 'quintoandar' and utm_medium in ('header', 'footer') then 'Online Free'
			when lead_origin ='Landing' and utm_source like 'facebook%' and utm_medium = 'social' then 'Online Free'
			when lead_type = 'BrokenOpenLink' then 'Online Free'
			when utm_source = 'mkt_supply' then 'Online Free'
			when utm_medium is null and utm_source is null then 'Online Free'
			else 'Online Paid'
		end as mkt_channel,
		case
			when lead_origin = 'Reprocessado' then null -- we will fill this later with reprocessed_lead_id
			when isales_direct_register or cx_direct_register then 'Admin'
			when lead_origin = 'Facebook' then 'Online Lead Ads'
			when b2b_lead then 'B2B Landing Page Form'
			when mkt_flow = 'Self-Service' and mkt_channel_type = 'Online' then 'Online Owner App'
			when mkt_flow = 'Self-Service' and mkt_channel_type = 'Affiliates' then 'IndicaAi Owner App'
			when mkt_flow = 'Other' and mkt_channel_type = 'Online' then 'Online Other'
			when mkt_channel_type = 'Online' then 'Online Landing Page Form'
			when lead_origin = 'Crawling' then 'Crawling'
			when doorman_lead and (lead_origin = 'Form' or lead_origin is null) then 'Doorman Whatsapp'
			when doorman_lead then 'Doorman Other'
			when lead_type = 'OpenLink' then 'IndicaAi Landing Page Form'
			when lead_type = 'Afiliado' and lead_origin = 'App' then 'IndicaAi Form'
			when lead_type = 'Afiliado' and lead_origin = 'Form' then 'IndicaAi App'
			when lead_type = 'Afiliado' and lead_origin = 'Desconhecida' then 'IndicaAi Unknown'
			when lead_type = 'Afiliado' and lead_origin = 'Planilha' then 'IndicaAi Spreadsheet'
			else null
		end as mkt_platform,
		case
			when lead_origin = 'Reprocessado' then null -- we will fill this later with reprocessed_lead_id
			when trim(utm_medium) like 'display%' then 'Display'
			when lead_origin = 'Facebook' then 'Display'
			when trim(utm_medium) = 'retargeting' then 'Retargeting'
			when lead_type = 'OpenLink' and utm_medium is null then 'Product'
			when trim(utm_medium) = 'email' then 'Email'
			when trim(utm_medium) = 'product' then 'Product'
			when trim(utm_medium) = 'whatsapp' then 'Whatsapp'
			when trim(utm_medium) = 'profilepage' then 'Profile page'
			when branded_lead then 'SEM branded'
			when trim(utm_medium) = 'cpc' then 'SEM non-branded'
			when trim(utm_medium) = 'affiliates' then 'Affiliate Networks'
			when trim(utm_medium) = 'classifieds' then 'Classifieds'
			when trim(utm_medium) = 'facebook' then 'Facebook'
			when trim(utm_source) = 'quintoandar' then 'Organic'
			when trim(utm_medium) = 'social' then 'Social'
			when utm_medium is null and utm_source is null and mkt_channel_type = 'Online' then 'Organic'
			when trim(utm_source) in ('google','bing') then 'SEM non-branded'
			when mkt_flow = 'Other' then 'Other'
			else null
		end as mkt_medium,
		case
			when lead_origin = 'Reprocessado' then null -- we will fill this later with reprocessed_lead_id
			when trim(utm_source) = 'directreferral' then 'Direct Referral'
			when trim(utm_source) like 'facebook%' then 'Facebook'
			when trim(utm_source) like 'google%' then 'Google'
			when trim(utm_source) = 'bing' then 'Bing'
			when trim(utm_source) like 'facebook%' then 'Facebook'
			when trim(utm_source) = 'rtbhouse' then 'RTB House'
			when trim(utm_source) = 'Zap' then 'Zap'
			when trim(utm_source) = 'ybox' then 'Ybox'
			when trim(utm_source) = 'quintoandar' then 'Organic'
			when utm_medium is null and utm_source is null and mkt_channel_type = 'Online' then 'Organic'
			when mkt_flow = 'Other' then 'Other'
			else null
		end as mkt_source
	from
		initial_categories
)
select
	ods_id,
	sk_lead,
	sk_conversion,
	sk_photo_job,
	sk_property,
	sk_user_rep,
	sk_user_sales_rep,
	sk_user_affiliate,
	sk_user_task_assignee,
	sk_user_owner,
	sk_user_photographer,
	sk_region,
	sk_lead_date,
	sk_prospect_date,
	sk_task_created_date,
	sk_first_inside_sales_contact_date,
	sk_conversion_date,
	sk_qualified_date,
	sk_opportunity_date,
	sk_first_listing_date,
	flow,
	acquisition_method,
	acquisition_channel,
	acquisition_source,
	funnel_step,
	funnel_drop_reason,
	lead_to_prospect_diff_minutes,
	prospect_to_qualified_diff_minutes,
	lead_to_first_inside_sales_contact_diff_minutes,
	prospect_to_first_inside_sales_contact_diff_minutes,
	qualified_to_opportunity_diff_minutes,
	opportunity_to_listing_diff_minutes,
	lead_to_listing_diff_minutes,
	lead_to_prospect_diff_hours,
	prospect_to_qualified_diff_hours,
	lead_to_first_inside_sales_contact_diff_hours,
	prospect_to_first_inside_sales_contact_diff_hours,
	qualified_to_opportunity_diff_hours,
	opportunity_to_listing_diff_hours,
	lead_to_listing_diff_hours,
	lead_to_prospect_diff_days,
	prospect_to_qualified_diff_days,
	lead_to_first_inside_sales_contact_diff_days,
	prospect_to_first_inside_sales_contact_diff_days,
	qualified_to_opportunity_diff_days,
	opportunity_to_listing_diff_days,
	lead_to_listing_diff_days,
	exclusivity,
	lead_type,
	lead_origin,
	utm_source as lead_utm_source,
	utm_medium as lead_utm_medium,
	branded_lead as branded_flg,
	b2b_lead as b2b_flg,
	doorman_lead as doorman_flg,
	isales_direct_register as isales_direct_register_flg,
	cx_direct_register as cx_direct_register_flg,
	isales_intervention as isales_intervention_flg,
	mkt_branded,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_channel_type,
	mkt_channel,
	case when lead_origin = 'Reprocessado' then trim(concat('Reprocessed ',mkt_platform)) else mkt_platform end as mkt_platform,
	mkt_medium,
	mkt_source
from
	final_categories
