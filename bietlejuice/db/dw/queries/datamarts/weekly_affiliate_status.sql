with all_leads as (select
fhl.sk_lead,
fhl.sk_lead_date,
dt_lead.date as date_affiliate_lead,
duaf.sk_user_affiliate as id_affiliate,
date(ts_joined_program) as date_join_program,
rank() over(partition by id_affiliate order by sk_lead_date,sk_lead) as rank_asc,
rank() over(partition by id_affiliate order by sk_lead_date desc,sk_lead desc) as rank_desc
from public.dim_user_affiliate duaf
left join public.dim_user du on du.dados_afiliado_id = duaf.sk_user_affiliate
left join public.fact_house_listing_flows fhl on fhl.sk_user_lead_affiliate = du.sk_user
left join public.dim_date as dt_lead on fhl.sk_lead_date = dt_lead.sk_date
where duaf.type = 'Standard'
group by 1,2,3,4,5
),
last_lead as (
select sk_lead,id_affiliate,date_affiliate_lead from all_leads
where rank_desc = 1
),
second_last_lead as (
select sk_lead,id_affiliate,date_affiliate_lead from all_leads
where rank_desc = 2
),
first_lead as (
select sk_lead,id_affiliate,date_affiliate_lead from all_leads
where rank_asc = 1
)
select
	al.id_affiliate,
	al.date_join_program,
	fl.sk_lead as first_sk_lead,
	fl.date_affiliate_lead as date_first_lead,
	sll.sk_lead as second_from_last_sk_lead,
	sll.date_affiliate_lead as date_second_from_last_lead,
	le.sk_lead as last_sk_lead,
	le.date_affiliate_lead as date_last_lead,
	case when coalesce(al.sk_lead,0) <= 0 then 'Inactive'
		 when coalesce(datediff(days,al.date_join_program,fl.date_affiliate_lead),0) <= 10 then 'New'
		 when coalesce(datediff(days,sll.date_affiliate_lead,le.date_affiliate_lead),0) <= 30 then 'Recurrent'
		 else 'Reengaging'
	end as status_affiliate,
	current_timestamp as ts_load
from all_leads al
left join last_lead le on al.id_affiliate = le.id_affiliate
left join second_last_lead sll on al.id_affiliate = sll.id_affiliate
left join first_lead fl on al.id_affiliate = fl.id_affiliate
group by 1,2,3,4,5,6,7,8,9
