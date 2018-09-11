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
),
taxonomy as (
    select
        ts.lead_type,
        ts.lead_origin,
        ts.lead_utm_source,
        ts.lead_utm_medium,
        ts.flg_branded::int::boolean,
        ts.flg_b2b::int::boolean,
        ts.flg_doorman::int::boolean,
        ts.flg_isales_direct_register::int::boolean,
        ts.flg_cx_direct_register::int::boolean,
        ts.flg_isales_intervention::int::boolean,
        ts.flg_callcenter::int::boolean,
        ts.mkt_category,
        ts.mkt_flow,
        ts.mkt_completion,
        ts.mkt_channel,
        ts.mkt_platform,
        ts.mkt_medium,
        ts.mkt_source
    from
        files.taxonomy_supply ts
)
select
	pl.ods_id,
	pl.sk_lead,
	pl.sk_conversion,
	pl.sk_photo_job,
	pl.sk_property,
	pl.sk_user_rep,
	pl.sk_user_sales_rep,
	pl.sk_user_affiliate,
	pl.sk_user_task_assignee,
	pl.sk_user_owner,
	pl.sk_user_photographer,
	pl.sk_region,
	pl.sk_lead_date,
	pl.sk_prospect_date,
	pl.sk_task_created_date,
	pl.sk_task_closed_date,
	pl.sk_first_inside_sales_contact_date,
	pl.sk_conversion_date,
	pl.sk_qualified_date,
	pl.sk_opportunity_date,
	pl.sk_first_listing_date,
	pl.flow,
	pl.acquisition_method,
	pl.acquisition_channel,
	pl.acquisition_source,
	pl.funnel_step,
	pl.funnel_drop_reason,
	pl.lead_to_prospect_diff_minutes,
	pl.prospect_to_qualified_diff_minutes,
	pl.lead_to_first_inside_sales_contact_diff_minutes,
	pl.prospect_to_first_inside_sales_contact_diff_minutes,
	pl.qualified_to_opportunity_diff_minutes,
	pl.opportunity_to_listing_diff_minutes,
	pl.lead_to_listing_diff_minutes,
	pl.lead_to_prospect_diff_hours,
	pl.prospect_to_qualified_diff_hours,
	pl.lead_to_first_inside_sales_contact_diff_hours,
	pl.prospect_to_first_inside_sales_contact_diff_hours,
	pl.qualified_to_opportunity_diff_hours,
	pl.opportunity_to_listing_diff_hours,
	pl.lead_to_listing_diff_hours,
	pl.lead_to_prospect_diff_days,
	pl.prospect_to_qualified_diff_days,
	pl.lead_to_first_inside_sales_contact_diff_days,
	pl.prospect_to_first_inside_sales_contact_diff_days,
	pl.qualified_to_opportunity_diff_days,
	pl.opportunity_to_listing_diff_days,
	pl.lead_to_listing_diff_days,
	pl.exclusivity,
	pl.lead_type,
	pl.lead_origin,
	pl.utm_source as lead_utm_source,
	pl.utm_medium as lead_utm_medium,
	pl.branded_lead as flg_branded,
	pl.b2b_lead as flg_b2b,
	pl.doorman_lead as flg_doorman,
	pl.isales_direct_register as flg_isales_direct_register,
	pl.cx_direct_register as flg_cx_direct_register,
	pl.isales_intervention as flg_isales_intervention,
	pl.flg_callcenter,
	case
        when pl.branded_lead then 'Branded'
        else 'Other'
	end as mkt_branded,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_category end as mkt_category,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_flow end as mkt_flow,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_completion end as mkt_completion,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_channel end as mkt_channel,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_platform end as mkt_platform,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_medium end as mkt_medium,
	case when t.mkt_flow is null then 'Not Mapped' else t.mkt_source end as mkt_source,
    now() as dt_timestamp
from
    potential_listings pl
left join
    taxonomy t
on
    coalesce(pl.lead_type,'') = coalesce(t.lead_type,'')
	and coalesce(pl.lead_origin,'') = coalesce(t.lead_origin,'')
	and coalesce(pl.utm_source,'') = coalesce(t.lead_utm_source,'')
	and coalesce(pl.utm_medium,'') = coalesce(t.lead_utm_medium,'')
	and coalesce(pl.branded_lead,false) = coalesce(t.flg_branded,false)
	and coalesce(pl.b2b_lead,false) = coalesce(t.flg_b2b,false)
	and coalesce(pl.doorman_lead,false) = coalesce(t.flg_doorman,false)
	and coalesce(pl.isales_direct_register,false) = coalesce(t.flg_isales_direct_register,false)
	and coalesce(pl.cx_direct_register,false) = coalesce(t.flg_cx_direct_register,false)
	and coalesce(pl.isales_intervention,false) = coalesce(t.flg_isales_intervention,false)
	and coalesce(pl.flg_callcenter,false) = coalesce(t.flg_callcenter,false)

