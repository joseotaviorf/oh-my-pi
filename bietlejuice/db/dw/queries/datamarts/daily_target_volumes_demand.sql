with share_local_holidays_by_city_group as (
with holidays_by_city_name as (
	select distinct
		dd.date,
		dd.week_start,
		coalesce(hs.weekday_name, dd.weekday_name) as weekday_name,
		coalesce(nullif(lh.city_group, ''), dr.city_group) as city_group,
		coalesce(nullif(lh.city_name, ''), dr.city_name) as city_name,
		coalesce(max(cast(replace(cs.share,',','') as float)), 0) as share_city_name,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.visit_booked,',','') as float)
			 else null end as visit_booked_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.visit_completed,',','') as float)
			 else null end as visit_completed_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.offer_submitted,',','') as float)
			 else null end as offer_submitted_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.offer_accepted,',','') as float)
			 else null end as offer_accepted_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.document_sent,',','') as float)
			 else null end as document_sent_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.credit_approved,',','') as float)
			 else null end as credit_approved_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.contract_signed,',','') as float)
			 else null end as contract_signed_share_holiday
	from dim_date dd
	cross join dim_region dr
	left join datalake_raw.gsheets_local_holidays lh
	  on dd.date = cast(replace(lh.date,'-','') as date) and (lh.short_region_name = dr.short_region_name or lh.city_group = dr.city_group)  
	left join datalake_raw.gsheets_city_share cs
	  on coalesce(nullif(lh.city_name, ''), dr.city_name) = nullif(cs.city_name, '')
	left join datalake_raw.gsheets_weekday_holiday_share hs
	  on hs.weekday_name = dd.weekday_name 
	where dd.date between '2018-12-31' and current_date + interval '6 months'
	group by dd.date,
		dd.week_start,
		lh.city_group,
		dr.city_group,
		lh.city_name,
		dr.city_name,
		hs.weekday_name,
		dd.weekday_name,
		dd.is_brz_holiday,
		hs.visit_booked,
		hs.visit_completed,
		hs.offer_submitted,
		hs.offer_accepted,
		hs.document_sent,
		hs.credit_approved,
		hs.contract_signed
	)
	SELECT 
		date,
		week_start,
		weekday_name,
		city_group,
		sum(share_city_name * coalesce(visit_booked_share_holiday,1)) as share_holiday_visit_booked,
		sum(share_city_name * coalesce(visit_completed_share_holiday,1)) as share_holiday_visit_completed,
		sum(share_city_name * coalesce(offer_submitted_share_holiday,1)) as share_holiday_offer_submitted,
		sum(share_city_name * coalesce(offer_accepted_share_holiday,1)) as share_holiday_offer_accepted,
		sum(share_city_name * coalesce(document_sent_share_holiday,1)) as share_holiday_document_sent,
		sum(share_city_name * coalesce(credit_approved_share_holiday,1)) as share_holiday_credit_approved,
		sum(share_city_name * coalesce(contract_signed_share_holiday,1)) as share_holiday_contract_signed
	from holidays_by_city_name
	where city_group is not null
	group by 1, 2, 3, 4
), final_shares as (
select distinct
	lhc.date,
	lhc.week_start,
	wd.city_group,
	wd.demand_channel_type,
	dcs.demand_channel,
	wd.funnel_first_touchpoint,
	cast(replace(wd.visit_booked,',','') as float) * cast(replace(dcs.visit_booked,',','') as float) as final_share_wo_holiday_visits_booked,
	cast(replace(wd.visit_booked,',','') as float) * lhc.share_holiday_visit_booked * cast(replace(dcs.visit_booked,',','') as float) as final_share_visits_booked,
	cast(replace(wd.visit_completed,',','') as float) * cast(replace(dcs.visit_completed,',','') as float) as final_share_wo_holiday_visits_completed,
	cast(replace(wd.visit_completed,',','') as float) * lhc.share_holiday_visit_completed * cast(replace(dcs.visit_completed,',','') as float) as final_share_visits_completed,
	cast(replace(wd.offer_submitted,',','') as float) * cast(replace(dcs.offer_submitted,',','') as float) as final_share_wo_holiday_offer_submitted,
	cast(replace(wd.offer_submitted,',','') as float) * lhc.share_holiday_offer_submitted * cast(replace(dcs.offer_submitted,',','') as float) as final_share_offer_submitted,
	cast(replace(wd.offer_accepted,',','') as float) * cast(replace(dcs.offer_accepted,',','') as float) as final_share_wo_holiday_offer_accepted,
	cast(replace(wd.offer_accepted,',','') as float) * lhc.share_holiday_offer_accepted * cast(replace(dcs.offer_accepted,',','') as float) as final_share_offer_accepted,
	cast(replace(wd.credit_evaluation_init,',','') as float) * cast(replace(dcs.credit_evaluation_init,',','') as float) as final_share_wo_holiday_credit_evaluation_init,
	cast(replace(wd.credit_evaluation_init,',','') as float) * lhc.share_holiday_offer_accepted * cast(replace(dcs.credit_evaluation_init,',','') as float) as final_share_credit_evaluation_init,
	cast(replace(wd.credit_evaluation_positive,',','') as float) * cast(replace(dcs.credit_evaluation_positive,',','') as float) as final_share_wo_holiday_credit_evaluation_positive,
	cast(replace(wd.credit_evaluation_positive,',','') as float) * lhc.share_holiday_offer_accepted * cast(replace(dcs.credit_evaluation_positive,',','') as float) as final_share_credit_evaluation_positive,
	cast(replace(wd.document_sent,',','') as float) * cast(replace(dcs.document_sent,',','') as float) as final_share_wo_holiday_document_sent,
	cast(replace(wd.document_sent,',','') as float) * lhc.share_holiday_document_sent * cast(replace(dcs.document_sent,',','') as float) as final_share_document_sent,
	cast(replace(wd.credit_approved,',','') as float) * cast(replace(dcs.credit_approved,',','') as float) as final_share_wo_holiday_credit_approved,
	cast(replace(wd.credit_approved,',','') as float) * lhc.share_holiday_credit_approved * cast(replace(dcs.credit_approved,',','') as float) as final_share_credit_approved,
	cast(replace(wd.contract_signed,',','') as float) * cast(replace(dcs.contract_signed,',','') as float) as final_share_wo_holiday_contract_signed,
	cast(replace(wd.contract_signed,',','') as float) * lhc.share_holiday_contract_signed * cast(replace(dcs.contract_signed,',','') as float) as final_share_contract_signed
from share_local_holidays_by_city_group lhc
left join datalake_raw.gsheets_weekday_demand_share wd
  on wd.weekday_name = lhc.weekday_name and wd.city_group = lhc.city_group
left join datalake_raw.gsheets_demand_channel_share dcs
  on dcs.city_group = lhc.city_group and cast(replace(dcs.week_start,'-','') as date) = lhc.week_start
), diff_w_and_wo_holiday_share as (
select
	fsh.date,
	fsh.week_start,
	fsh.city_group,
	fsh.demand_channel_type,
	fsh.demand_channel,
	wv.guarantee,
	fsh.funnel_first_touchpoint,
	sum(fsh.final_share_visits_booked * cast(replace(wv.visit_booked,',','') as float)) as visit_booked_1,
	sum(fsh.final_share_visits_booked * cast(replace(wv.visit_booked,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_visit_booked_daily,
	sum(fsh.final_share_wo_holiday_visits_booked * cast(replace(wv.visit_booked,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_visit_booked_daily_wo_holiday,
	sum(fsh.final_share_visits_completed * cast(replace(wv.visit_completed,',','') as float)) as visit_completed_1,
	sum(fsh.final_share_visits_completed * cast(replace(wv.visit_completed,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_visit_completed_daily,
	sum(fsh.final_share_wo_holiday_visits_completed * cast(replace(wv.visit_completed,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_visit_completed_daily_wo_holiday,
	sum(fsh.final_share_offer_submitted * cast(replace(wv.offer_submitted,',','') as float)) as offer_submitted_1,
	sum(fsh.final_share_offer_submitted * cast(replace(wv.offer_submitted,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_offer_submitted_daily,
	sum(fsh.final_share_wo_holiday_offer_submitted * cast(replace(wv.offer_submitted,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_offer_submitted_daily_wo_holiday,
	sum(fsh.final_share_offer_accepted * cast(replace(wv.offer_accepted,',','') as float)) as offer_accepted_1,
	sum(fsh.final_share_offer_accepted * cast(replace(wv.offer_accepted,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_offer_accepted_daily,
	sum(fsh.final_share_wo_holiday_offer_accepted * cast(replace(wv.offer_accepted,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_offer_accepted_daily_wo_holiday,
	sum(fsh.final_share_credit_evaluation_init * cast(replace(wv.credit_evaluation_init,',','') as float)) as credit_evaluation_init_1,
	sum(fsh.final_share_credit_evaluation_init * cast(replace(wv.credit_evaluation_init,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_evaluation_init_daily,
	sum(fsh.final_share_wo_holiday_credit_evaluation_init * cast(replace(wv.credit_evaluation_init,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_evaluation_init_daily_wo_holiday,
	sum(fsh.final_share_credit_evaluation_positive * cast(replace(wv.credit_evaluation_positive,',','') as float)) as credit_evaluation_positive_1,
	sum(fsh.final_share_credit_evaluation_positive * cast(replace(wv.credit_evaluation_positive,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_evaluation_positive_daily,
	sum(fsh.final_share_wo_holiday_credit_evaluation_positive * cast(replace(wv.credit_evaluation_positive,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_evaluation_positive_daily_wo_holiday,
	sum(fsh.final_share_document_sent * cast(replace(wv.document_sent,',','') as float)) as document_sent_1,
	sum(fsh.final_share_document_sent * cast(replace(wv.document_sent,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_document_sent_daily,
	sum(fsh.final_share_wo_holiday_document_sent * cast(replace(wv.document_sent,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_document_sent_daily_wo_holiday,
	sum(fsh.final_share_credit_approved * cast(replace(wv.credit_approved,',','') as float)) as credit_approved_1,
	sum(fsh.final_share_credit_approved * cast(replace(wv.credit_approved,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_approved_daily,
	sum(fsh.final_share_wo_holiday_credit_approved * cast(replace(wv.credit_approved,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_credit_approved_daily_wo_holiday,
	sum(fsh.final_share_contract_signed * cast(replace(wv.contract_signed,',','') as float)) as contract_signed_1,
	sum(fsh.final_share_contract_signed * cast(replace(wv.contract_signed,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_contract_signed_daily,
	sum(fsh.final_share_wo_holiday_contract_signed * cast(replace(wv.contract_signed,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_contract_signed_daily_wo_holiday,
	sum(fsh.final_share_visits_booked * cast(replace(wv.new_tenant_prospect,',','') as float)) as new_tenant_prospect_1,
	sum(fsh.final_share_visits_booked * cast(replace(wv.new_tenant_prospect,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_new_tenant_prospect_daily,
	sum(fsh.final_share_wo_holiday_visits_booked * cast(replace(wv.new_tenant_prospect,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) as total_new_tenant_prospect_daily_wo_holiday
from final_shares fsh
join datalake_raw.gsheets_week_volumes_demand wv
  on fsh.city_group = wv.city_group
  	and fsh.week_start = cast(replace(wv.week_start,'-','') as date)
  	and fsh.demand_channel_type = wv.demand_channel_type
  	and fsh.funnel_first_touchpoint = wv.funnel_first_touchpoint
group by 1,2,3,4,5,6,7,
	fsh.final_share_visits_booked,
	wv.visit_booked,
	fsh.final_share_wo_holiday_visits_booked,
	fsh.final_share_visits_completed,
	wv.visit_completed,
	fsh.final_share_wo_holiday_visits_completed,
	fsh.final_share_credit_approved,
	wv.credit_approved,
	fsh.final_share_wo_holiday_credit_approved,
	fsh.final_share_contract_signed,
	wv.contract_signed,
	fsh.final_share_wo_holiday_contract_signed,
	fsh.final_share_offer_submitted,
	wv.offer_submitted,
	fsh.final_share_wo_holiday_offer_submitted,
	fsh.final_share_offer_accepted,
	wv.offer_accepted,
	fsh.final_share_wo_holiday_offer_accepted,
	fsh.final_share_credit_evaluation_init,
	wv.credit_evaluation_init,
	fsh.final_share_wo_holiday_credit_evaluation_init,
	fsh.final_share_credit_evaluation_positive,
	wv.credit_evaluation_positive,
	fsh.final_share_wo_holiday_credit_evaluation_positive,
	fsh.final_share_document_sent,
	wv.document_sent,
	fsh.final_share_wo_holiday_document_sent,
	wv.new_tenant_prospect
), daily_target_shares as (
SELECT 
	date,
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	visit_booked_1 + case when total_visit_booked_daily > 0 then (total_visit_booked_daily_wo_holiday - total_visit_booked_daily) * visit_booked_1 / total_visit_booked_daily else 0 end as visit_booked,
	visit_completed_1 + case when total_visit_completed_daily > 0 then (total_visit_completed_daily_wo_holiday - total_visit_completed_daily) * visit_completed_1 / total_visit_completed_daily else 0 end as visit_completed,
	offer_submitted_1 + case when total_offer_submitted_daily > 0 then (total_offer_submitted_daily_wo_holiday - total_offer_submitted_daily) * offer_submitted_1 / total_offer_submitted_daily else 0 end as offer_submitted,
	offer_accepted_1 + case when total_offer_accepted_daily > 0 then (total_offer_accepted_daily_wo_holiday - total_offer_accepted_daily) * offer_accepted_1 / total_offer_accepted_daily else 0 end as offer_accepted,
	credit_evaluation_init_1 + case when total_credit_evaluation_init_daily > 0 then (total_credit_evaluation_init_daily_wo_holiday - total_credit_evaluation_init_daily) * credit_evaluation_init_1 / total_credit_evaluation_init_daily else 0 end as credit_evaluation_init,
	credit_evaluation_positive_1 + case when total_credit_evaluation_positive_daily > 0 then (total_credit_evaluation_positive_daily_wo_holiday - total_credit_evaluation_positive_daily) * credit_evaluation_positive_1 / total_credit_evaluation_positive_daily else 0 end as credit_evaluation_positive,
	document_sent_1 + case when total_document_sent_daily > 0 then (total_document_sent_daily_wo_holiday - total_document_sent_daily) * document_sent_1 / total_document_sent_daily else 0 end as document_sent,
	credit_approved_1 + case when total_credit_approved_daily > 0 then (total_credit_approved_daily_wo_holiday - total_credit_approved_daily) * credit_approved_1 / total_credit_approved_daily else 0 end as credit_approved,
	contract_signed_1 + case when total_contract_signed_daily > 0 then (total_contract_signed_daily_wo_holiday - total_contract_signed_daily) * contract_signed_1 / total_contract_signed_daily else 0 end as contract_signed,
	new_tenant_prospect_1 + case when total_new_tenant_prospect_daily > 0 then (total_new_tenant_prospect_daily_wo_holiday - total_new_tenant_prospect_daily) * new_tenant_prospect_1 / total_new_tenant_prospect_daily else 0 end as new_tenant_prospect
from diff_w_and_wo_holiday_share 
), gsheets_demand_target_adjusted as (
WITH
demand_targets AS (
	SELECT * FROM datalake_raw.gsheets_demand_targets_2021 
    UNION ALL
	    SELECT * FROM datalake_raw.gsheets_demand_targets_2020 
    UNION ALL
        SELECT * FROM datalake_raw.gsheets_demand_targets_2019
)
SELECT
  cast(replace(date,'-','') as date) as date,
	cast(replace(week_start,'-','') as date) as week_start,
	nullif(city_group, '') as city_group,
	nullif(demand_channel_type, '') as demand_channel_type,
	nullif(demand_channel, '') as demand_channel,
	nullif(funnel_origin, '') as funnel_first_touchpoint,
	nullif(guarantee, '') as guarantee,
	cast(replace(visits_booked,',','') as float) as visit_booked,
	cast(replace(visits_completed,',','') as float) as visit_completed,
	cast(replace(offer_sent,',','') as float) as offer_submitted,
	cast(replace(offer_accepted,',','') as float) as offer_accepted,
	cast(replace(evaluation_started,',','') as float) as credit_evaluation_init,
	cast(replace(evaluation_positive,',','') as float) as credit_evaluation_positive,
	cast(replace(doc_sent,',','') as float) as document_sent,
	cast(replace(credit_approved,',','') as float) credit_approved,
	cast(replace(contracts_signed,',','') as float) as contract_signed,
	cast(replace(new_tenant_prospects,',','') as float) as new_tenant_prospect
FROM demand_targets
where date_trunc('month', cast(replace(date,'-','') as date)) < date_trunc('month', current_date)
), past_targets as (
select 
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	sum(visit_booked) as vb_congelado,
	sum(visit_completed) as vc_congelado,
	sum(offer_submitted) as os_congelado,
	sum(offer_accepted) as oa_congelado,
	sum(credit_evaluation_init) as cei_congelado,
	sum(credit_evaluation_positive) as cep_congelado,
	sum(document_sent) as ds_congelado,
	sum(credit_approved) as ca_congelado,
	sum(contract_signed) as cs_congelado,
	sum(new_tenant_prospect) as ntp_congelado
from gsheets_demand_target_adjusted
group by 1,2,3,4,5,6
), calculated_targets as (
select
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	sum(visit_booked) as vb_calculado,
	sum(visit_completed) as vc_calculado,
	sum(offer_submitted) as os_calculado,
	sum(offer_accepted) as oa_calculado,
	sum(credit_evaluation_init) as cei_calculado,
	sum(credit_evaluation_positive) as cep_calculado,
	sum(document_sent) as ds_calculado,
	sum(credit_approved) as ca_calculado,
	sum(contract_signed) as cs_calculado,
	sum(new_tenant_prospect) as ntp_calculado
from daily_target_shares
group by 1,2,3,4,5,6
), targets_diff as (
select
	ct.week_start,
	ct.city_group,
	ct.demand_channel_type,
	ct.demand_channel,
	ct.funnel_first_touchpoint,
	ct.guarantee,
	coalesce(ct.vb_calculado,0) - coalesce(pt.vb_congelado,0) as diff_vb,
	coalesce(ct.vc_calculado,0) - coalesce(pt.vc_congelado,0) as diff_vc,
	coalesce(ct.os_calculado,0) - coalesce(pt.os_congelado,0) as diff_os,
	coalesce(ct.oa_calculado,0) - coalesce(pt.oa_congelado,0) as diff_oa,
	coalesce(ct.cei_calculado,0) - coalesce(pt.cei_congelado,0) as diff_cei,
	coalesce(ct.cep_calculado,0) - coalesce(pt.cep_congelado,0) as diff_cep,
	coalesce(ct.ds_calculado,0) - coalesce(pt.ds_congelado,0) as diff_ds,
	coalesce(ct.ca_calculado,0) - coalesce(pt.ca_congelado,0) as diff_ca,
	coalesce(ct.cs_calculado,0) - coalesce(pt.cs_congelado,0) as diff_cs,
	coalesce(ct.ntp_calculado,0) - coalesce(pt.ntp_congelado,0) as diff_ntp
from calculated_targets ct
left join past_targets pt
  on ct.week_start = pt.week_start
    and ct.city_group = pt.city_group
	and ct.demand_channel_type = pt.demand_channel_type
	and ct.demand_channel = pt.demand_channel
	and ct.funnel_first_touchpoint = pt.funnel_first_touchpoint
	and ct.guarantee = pt.guarantee
), calculated_targets_week_month as (
SELECT
	date,
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	visit_booked as vb_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then visit_booked else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as vb_total_week,
	sum(visit_completed) as vc_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then visit_completed else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as vc_total_week,
	sum(offer_submitted) as os_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then offer_submitted else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as os_total_week,
	sum(offer_accepted) as oa_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then offer_accepted else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as oa_total_week,
	sum(credit_evaluation_init) as cei_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then credit_evaluation_init else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as cei_total_week,
	sum(credit_evaluation_positive) as cep_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then credit_evaluation_positive else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as cep_total_week,
	sum(document_sent) as ds_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then document_sent else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as ds_total_week,
	sum(credit_approved) as ca_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then credit_approved else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as ca_total_week,
	sum(contract_signed) as cs_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then contract_signed else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as cs_total_week,
	sum(new_tenant_prospect) as ntp_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then new_tenant_prospect else 0 end) over(partition by week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) as ntp_total_week
from daily_target_shares
group by 1, 2, 3, 4, 5, 6, 7, visit_booked, visit_completed, offer_submitted, offer_accepted, credit_evaluation_init, credit_evaluation_positive, document_sent, credit_approved, contract_signed, new_tenant_prospect
), daily_target_shares_adjusted as (
select distinct
	coalesce(g.date, d.date) as date,
	coalesce(g.week_start, d.week_start) as week_start,
	coalesce(g.city_group, d.city_group) as city_group,
	coalesce(g.demand_channel_type, d.demand_channel_type) as demand_channel_type,
	coalesce(g.demand_channel, d.demand_channel) as demand_channel,
	coalesce(g.funnel_first_touchpoint, d.funnel_first_touchpoint) as funnel_first_touchpoint,
	coalesce(g.guarantee, d.guarantee) as guarantee,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.visit_booked
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.vb_total_week != 0 and td.diff_vb != 0 then td.diff_vb * coalesce(wm.vb_calculado,0)/wm.vb_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.vb_total_week = 0 and td.diff_vb != 0 then td.diff_vb
			else d.visit_booked end as visit_booked,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.visit_completed
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.vc_total_week != 0 and td.diff_vc != 0 then td.diff_vc * coalesce(wm.vc_calculado,0)/wm.vc_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.vc_total_week = 0 and td.diff_vc != 0 then td.diff_vc
			else d.visit_completed end as visit_completed,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.offer_submitted
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.os_total_week != 0 and td.diff_os != 0 then td.diff_os * coalesce(wm.os_calculado,0)/wm.os_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.os_total_week = 0 and td.diff_os != 0 then td.diff_os
			else d.offer_submitted end as offer_submitted,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.offer_accepted
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.oa_total_week != 0 and td.diff_oa != 0 then td.diff_oa * coalesce(wm.oa_calculado,0)/wm.oa_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.oa_total_week = 0 and td.diff_oa != 0 then td.diff_oa
			else d.offer_accepted end as offer_accepted,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.credit_evaluation_init
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cei_total_week != 0 and td.diff_cei != 0 then td.diff_cei * coalesce(wm.cei_calculado,0)/wm.cei_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cei_total_week = 0 and td.diff_cei != 0 then td.diff_cei
			else d.credit_evaluation_init end as credit_evaluation_init,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.credit_evaluation_positive
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cep_total_week != 0 and td.diff_cep != 0 then td.diff_cep * coalesce(wm.cep_calculado,0)/wm.cep_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cep_total_week = 0 and td.diff_cep != 0 then td.diff_cep
			else d.credit_evaluation_positive end as credit_evaluation_positive,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.document_sent
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ds_total_week != 0 and td.diff_ds != 0 then td.diff_ds * coalesce(wm.ds_calculado,0)/wm.ds_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ds_total_week = 0 and td.diff_ds != 0 then td.diff_ds
			else d.document_sent end as document_sent,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.credit_approved
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ca_total_week != 0 and td.diff_ca != 0 then td.diff_ca * coalesce(wm.ca_calculado,0)/wm.ca_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ca_total_week = 0 and td.diff_ca != 0 then td.diff_ca
			else d.credit_approved end as credit_approved,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.contract_signed
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cs_total_week != 0 and td.diff_cs != 0 then td.diff_cs * coalesce(wm.cs_calculado,0)/wm.cs_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.cs_total_week = 0 and td.diff_cs != 0 then td.diff_cs
			else d.contract_signed end as contract_signed,
	case when date_trunc('month', coalesce(g.date, d.date)) < date_trunc('month', current_date) then g.new_tenant_prospect
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ntp_total_week != 0 and td.diff_ntp != 0 then td.diff_ntp * coalesce(wm.ntp_calculado,0)/wm.ntp_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) >= date_trunc('month', current_date) and wm.ntp_total_week = 0 and td.diff_ntp != 0 then td.diff_ntp
			else d.new_tenant_prospect end as new_tenant_prospect
from daily_target_shares d
full outer join gsheets_demand_target_adjusted g
  on d.date = g.date
	and d.week_start = g.week_start
	and d.city_group = g.city_group
	and d.demand_channel_type = g.demand_channel_type
	and d.demand_channel = g.demand_channel
	and d.funnel_first_touchpoint = g.funnel_first_touchpoint
	and d.guarantee = g.guarantee
left join targets_diff td
  on td.week_start = d.week_start
    and d.city_group = td.city_group
	and d.demand_channel_type = td.demand_channel_type
	and d.demand_channel = td.demand_channel
	and d.funnel_first_touchpoint = td.funnel_first_touchpoint
	and d.guarantee = td.guarantee
left join calculated_targets_week_month wm
  on wm.date = d.date
    and wm.week_start = d.week_start
    and wm.city_group = d.city_group
    and wm.demand_channel_type = d.demand_channel_type
    and wm.demand_channel = d.demand_channel
    and wm.funnel_first_touchpoint = d.funnel_first_touchpoint
    and wm.guarantee = d.guarantee 
), negative_targets as (
select
	date,
	demand_channel_type,
	sum(case when visit_booked < 0 then visit_booked end) as vb_negative,
	sum(case when visit_completed < 0 then visit_completed end) as vc_negative,
	sum(case when offer_submitted < 0 then offer_submitted end) as os_negative,
	sum(case when offer_accepted < 0 then offer_accepted end) as oa_negative,
	sum(case when credit_evaluation_init < 0 then credit_evaluation_init end) as cei_negative,
	sum(case when credit_evaluation_positive < 0 then credit_evaluation_positive end) as cep_negative,
	sum(case when document_sent < 0 then document_sent end) as ds_negative,
	sum(case when credit_approved < 0 then credit_approved end) as ca_negative,
	sum(case when contract_signed < 0 then contract_signed end) as cs_negative,
	sum(case when new_tenant_prospect < 0 then new_tenant_prospect end) as ntp_negative
from daily_target_shares_adjusted
group by 1,2
)
select 
	dt.date,
	dt.week_start,
	dt.city_group,
	dt.demand_channel_type,
	dt.demand_channel,
	dt.funnel_first_touchpoint,
	dt.guarantee,
	case when visit_booked <= 0 then 0 else visit_booked + (coalesce(nt.vb_negative,0) * visit_booked/(sum(case when visit_booked > 0 then visit_booked end) over(partition by dt.date, dt.demand_channel_type))) end as visit_booked,
	case when visit_completed <= 0 then 0 else visit_completed + coalesce(nt.vc_negative,0) * visit_completed/(sum(case when visit_completed > 0 then visit_completed end) over(partition by dt.date, dt.demand_channel_type)) end as visit_completed,
	case when offer_submitted <= 0 then 0 else offer_submitted + coalesce(nt.os_negative,0) * offer_submitted/(sum(case when offer_submitted > 0 then offer_submitted end) over(partition by dt.date, dt.demand_channel_type)) end as offer_submitted,
	case when offer_accepted <= 0 then 0 else offer_accepted + coalesce(nt.oa_negative,0) * offer_accepted/(sum(case when offer_accepted > 0 then offer_accepted end) over(partition by dt.date, dt.demand_channel_type)) end as offer_accepted,
	case when credit_evaluation_init <= 0 then 0 else credit_evaluation_init + coalesce(nt.cei_negative,0) * credit_evaluation_init/(sum(case when credit_evaluation_init > 0 then credit_evaluation_init end) over(partition by dt.date, dt.demand_channel_type)) end as credit_evaluation_init,
	case when credit_evaluation_positive <= 0 then 0 else credit_evaluation_positive + coalesce(nt.cep_negative,0) * credit_evaluation_positive/(sum(case when credit_evaluation_positive > 0 then credit_evaluation_positive end ) over(partition by dt.date, dt.demand_channel_type)) end as credit_evaluation_positive,
	case when document_sent <= 0 then 0 else document_sent + coalesce(nt.ds_negative,0) * document_sent/(sum(case when document_sent > 0 then document_sent end) over(partition by dt.date, dt.demand_channel_type)) end as document_sent,
	case when credit_approved <= 0 then 0 else credit_approved + coalesce(nt.ca_negative,0) * credit_approved/(sum(case when credit_approved > 0 then credit_approved end ) over(partition by dt.date, dt.demand_channel_type)) end as credit_approved,
	case when contract_signed <= 0 then 0 else contract_signed + coalesce(nt.cs_negative,0) * contract_signed/(sum(case when contract_signed > 0 then contract_signed end ) over(partition by dt.date, dt.demand_channel_type)) end as contract_signed,
	case when new_tenant_prospect <= 0 then 0 else new_tenant_prospect + coalesce(nt.ntp_negative,0) * new_tenant_prospect/(sum(case when new_tenant_prospect > 0 then new_tenant_prospect end) over(partition by dt.date, dt.demand_channel_type)) end as new_tenant_prospect
from daily_target_shares_adjusted dt
left join negative_targets nt
  on dt.date = nt.date 
    and dt.demand_channel_type = nt.demand_channel_type;
