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
		coalesce(old_bl.lead_type, bl.lead_type) as lead_type,
		coalesce(old_bl.lead_origin, bl.lead_origin) as lead_origin,
		coalesce(old_bl.utm_source, bl.utm_source) as utm_source,
		coalesce(old_bl.utm_medium, bl.utm_medium) as utm_medium,
		coalesce(old_bl.branded_lead, bl.branded_lead) as branded_lead,
		coalesce(old_bl.b2b_lead, bl.b2b_lead) as b2b_lead,
		coalesce((bl.lead_origin = 'Reprocessado'), false) as reprocessed_flg
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
		coalesce(to_char(bt.dt_closed::date, 'YYYYMMDD')::integer, -1) as sk_task_closed_date,
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
		bl.reprocessed_flg,
		case
			when d.imovel_id is not null and acquisition_channel not like ('Reprocessed%')
			then true
			else (f.acquisition_source = 'Doorman')
		end as doorman_lead,
		(acquisition_channel = 'Inside Sales') as isales_direct_register,
		(acquisition_channel = 'Admin') as cx_direct_register,
		(coalesce(f.rep_id, bt.rep_id) is not null) as isales_intervention,
		(us_cad.id is not null) as flg_callcenter
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
	left join
		imovel i
		on f.imovel_id = i.id
	left join
		usuario us_cad
	    on us_cad.id = i.usuario_que_cadastrou_id
	    and us_cad.email like '%@hargos.com.br' -- Registered emails to callcenter company Hargos
), -- initial categories that will derivate others
initial_categories as (
	select
		*,
		case
			when lead_type = 'Afiliado' then 'Outbound'
			when lead_origin = 'Desconhecida' then 'Other'
			when reprocessed_flg then 'Outbound'
			when flg_callcenter then 'Outbound'
			when b2b_lead then 'Outbound'
			when doorman_lead then 'Outbound'
			when lead_origin = 'Crawling' then 'Outbound'
			when lead_type = 'OLX' and lead_origin is null then 'Outbound'
			when lead_origin = 'Reprocessado' then 'Outbound'
		    else 'Inbound'
		end as mkt_category,
		case
			when lead_origin = 'OwnerPWA' then 'Self-Service'
			when lead_type is null and lead_origin is null and
				not(coalesce(doorman_lead, false)) and not(coalesce(isales_direct_register, false)) and not(coalesce(cx_direct_register, false))
				and not(coalesce(flg_callcenter, false)) and not(coalesce(isales_intervention, false)) and not(coalesce(b2b_lead, false)) then 'Self-Service'
			else 'Non-Self Service'
		end as mkt_flow,
		case
			when branded_lead then 'Branded'
			else 'Other'
		end as mkt_branded,
		case
			when reprocessed_flg then 'Other'
			when lead_type in ('Afiliado', 'OpenLink', 'LandingOpenLink') then 'Affiliates'
			when b2b_lead or doorman_lead then 'Affiliates'
			when lead_type = 'Marketing' and lead_origin = 'Facebook' then 'Online Paid'
			when trim(utm_medium) = 'classifieds' then 'Online Classifieds'
			when branded_lead then 'Organic'
			when utm_source = 'quintoandar' and utm_medium in ('header', 'footer') then 'Organic'
			when (lead_type = 'LandingMarketing' or lead_origin = 'Landing') and utm_source like 'facebook%' and utm_medium = 'social' then 'Organic'
			when lead_type = 'BrokenOpenLink' then 'Organic'
			when utm_source = 'mkt_supply' then 'Organic'
			when lead_origin = 'Crawling' then 'Other'
			when isales_direct_register or cx_direct_register then 'Other'
			when lead_type = 'OLX' and lead_origin is null then 'Other'
			when lead_origin = 'Desconhecida' and (lead_type <> 'Afiliado' or lead_type is null) then 'Other'
			when lead_type = 'LandingMarketing' and lower(utm_source) in ('facebook', 'google', 'criteo', 'trovit') and not branded_lead then 'Online Paid'
			when lead_type = 'LandingMarketing' and (utm_source like 'facebook%' or utm_source like 'google%') and not branded_lead then 'Online Paid'
			when lead_type = 'Marketing' and (utm_source in ('criteo', 'rtbhouse', 'ybox', 'bing') or lower(utm_medium) like 'cpc%') then 'Online Paid'
			when lead_type = 'Marketing' and (utm_source like '%facebook%' or utm_source like '%google%') then 'Online Paid'
			when utm_medium is null and utm_source is null then 'Organic'
			when lead_type = 'Marketing' and utm_source is null then 'Online Paid'
			when lead_type = 'Marketing' and lower(utm_medium) = 'affiliates' then 'Online Paid'
			else 'Other'
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
			when reprocessed_flg then 'Recovered Leads'
			when doorman_lead then 'Doorman'
			when b2b_lead then 'B2B'
			when isales_direct_register then 'Lost Tracking'
			when cx_direct_register then 'Lost Tracking'
			when mkt_channel_type = 'Affiliates' then 'IndicaAi'
			when lead_origin = 'Desconhecida' and (lead_type <> 'Afiliado' or lead_type is null) then 'Other'
			when lead_origin = 'Crawling' or lead_type = 'OLX' or flg_callcenter then 'Crawling'
			when lower(utm_source) = 'directreferral' then 'Direct Referral'
			when mkt_channel_type in ('Online Paid', 'Organic', 'Online Classifieds') then null
			else 'Other'
		end as mkt_channel,
		case
			when flg_callcenter then 'Crawling Indirect'
			when isales_direct_register or cx_direct_register then 'Admin'
			when lead_origin = 'Facebook' then 'Online Lead Ads'
			when b2b_lead then 'B2B Landing Page Form'
			when lead_type = 'LandingOpenLink' and utm_source = 'directreferral' then 'IndicaAi Owner App'
			when lead_origin = 'OwnerPWA' and coalesce(utm_source,'') <> 'directreferral' then 'Online Owner App'
			when mkt_flow = 'Other' and mkt_channel_type = 'Online' then 'Online Other'
			when lead_origin = 'Crawling' then 'Crawling Direct'
			when lead_type = 'OLX' and lead_origin is null then 'Crawling Direct'
			when doorman_lead and (lead_origin = 'Form' or lead_origin is null) then 'Doorman Whatsapp'
			when doorman_lead then 'Doorman Other'
			when lead_type = 'OpenLink' then 'IndicaAi Landing Page Form'
			when lead_type = 'Afiliado' and lead_origin = 'Form' then 'IndicaAi Form'
			when lead_type = 'Afiliado' and lead_origin = 'App' then 'IndicaAi App'
			when lead_type = 'Afiliado' and lead_origin = 'Desconhecida' then 'IndicaAi Unknown'
			when lead_type = 'Afiliado' and lead_origin = 'Planilha' then 'IndicaAi Spreadsheet'
			when lead_origin in ('Reprocessado', 'Desconhecida') then 'Other'
			when lead_origin = 'Landing' then 'Online Landing Page Form'
			when reprocessed_flg and lead_origin = 'Landing' then 'Online Landing Page Form' -- reprocessed fallback
			when reprocessed_flg and lead_origin = 'OwnerPWA' then 'Online Owner App' -- reprocessed fallback
			else 'Other'
		end as mkt_platform,
		case
			when flg_callcenter then null
			when isales_direct_register then 'Inside Sales'
			when cx_direct_register then 'CX'
			when lower(utm_source) = 'directreferral' then 'Direct Referral'
			when reprocessed_flg then null -- we will fill this later with reprocessed_lead_id
			when doorman_lead then null
			when trim(utm_medium) like '%display%' then 'Display'
			when lower(utm_medium) in ('source', 'post') then 'Display'
			when lead_origin = 'Facebook' then 'Display'
			when trim(utm_medium) = 'retargeting' then 'Retargeting'
			when lead_type = 'OpenLink' and utm_medium is null then 'Product'
			when trim(utm_medium) = 'email' then 'Notifications'
			when trim(utm_medium) = 'product' then 'Product'
			when trim(utm_medium) = 'whatsapp' then 'Whatsapp'
			when trim(utm_medium) = 'profilepage' then 'Profile page'
			when branded_lead then 'SEM branded'
			when trim(lower(utm_medium)) = 'cpc' then 'SEM non-branded'
			when trim(utm_medium) like 'affiliate%' then 'Affiliate Networks'
			when trim(utm_medium) = 'classifieds' then 'Classifieds'
			when trim(utm_medium) = 'facebook' then 'Facebook'
			when trim(utm_source) = 'quintoandar' then 'Direct'
			when trim(utm_medium) = 'social' then 'Social'
			when lead_origin = 'Desconhecida' then null
			when lead_type = 'OLX' then null
			when utm_medium is null and utm_source is null and lead_type = 'Landing' then 'Direct'
			when utm_medium is null and utm_source is null and lead_type = 'OwnerPWA' then 'Direct'
			when utm_medium is null and utm_source is null and lead_type is null then 'Direct'
			when trim(utm_source) in ('google','bing') then 'SEM non-branded'
			when trim(utm_source) like 'google%' then 'SEM non-branded'
			when mkt_flow = 'Other' then 'Other'
			when mkt_channel_type = 'Organic' then 'Direct'
			when trim(lower(utm_source)) like 'facebook%' then 'Display'
			else null
		end as mkt_medium,
		case
		    when flg_callcenter then null
		    when isales_direct_register then 'Inside Sales'
			when cx_direct_register then 'CX'
			when doorman_lead then null
			when trim(utm_source) = 'directreferral' and utm_medium is null then null
			when trim(utm_source) = 'directreferral' and trim(utm_medium) = 'email' then 'Email'
			when trim(utm_source) = 'directreferral' and trim(utm_medium) = 'product' then 'Product'
			when trim(utm_source) = 'directreferral' and trim(utm_medium) = 'profilepage' then 'Profile Page'
			when trim(utm_source) = 'directreferral' and trim(utm_medium) = 'whatsapp' then 'Whatsapp'
			when trim(utm_source) like 'facebook%' or lead_origin = 'Facebook' or trim(utm_medium) = 'facebook' then 'Facebook'
			when trim(utm_source) like 'google%' then 'Google'
			when trim(utm_source) = 'bing' then 'Bing'
			when trim(utm_source) = 'rtbhouse' then 'RTB House'
			when trim(utm_source) = 'Zap' then 'Zap'
			when trim(utm_source) = 'ybox' then 'Ybox'
			when trim(utm_source) = 'quintoandar' then 'Direct'
			when trim(utm_source) = 'criteo' then 'Criteo'
			when trim(utm_source) = 'Trovit' then 'Trovit'
			when lead_origin = 'Desconhecida' then null
			when lead_type = 'OLX' then null
			when utm_medium is null and utm_source is null and lead_type = 'Landing' then 'Direct'
			when utm_medium is null and utm_source is null and lead_type = 'OwnerPWA' then 'Direct'
			when utm_medium is null and utm_source is null and lead_type is null then 'Direct'
			when trim(utm_medium) = 'affiliates' then lower(trim(utm_source))
			when mkt_flow = 'Other' then 'Other'
			when mkt_channel_type = 'Organic' then 'Direct'
			else null
		end as mkt_source,
        case
	        when lead_type = 'Organic' and lead_origin = 'OwnerPWA' then 'App Android'
	        when mkt_channel_type = 'Organic' and lead_type is null and lead_origin is null then 'App iOS'
            else null
        end as mkt_device
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
	sk_task_closed_date,
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
	branded_lead as flg_branded,
	b2b_lead as flg_b2b,
	doorman_lead as flg_doorman,
	isales_direct_register as flg_isales_direct_register,
	cx_direct_register as flg_cx_direct_register,
	isales_intervention as flg_isales_intervention,
	flg_callcenter,
	mkt_branded,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_channel_type,
	coalesce(mkt_channel, mkt_medium) as mkt_channel,
	case when reprocessed_flg then trim(concat('Recovered Leads ', mkt_platform)) else mkt_platform end as mkt_platform,
	mkt_medium,
	mkt_source,
	mkt_device,
    now() as dt_timestamp
from
	final_categories
