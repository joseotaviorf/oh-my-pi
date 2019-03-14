drop view if exists vw_lead_first_event_tracking;

create view vw_lead_first_event_tracking as
with t_union as (
	select
		lo_external_id.*
	from lead l
	join
		public.lead_origin lo_external_id
		on lo_external_id.e_formfield_lead_uuid =  l.external_id
			and lo_external_id.e_formfield_lead_uuid is not null
union all
	select
		lo_firestore_id.*
	from lead l
	join
		public.lead_origin lo_firestore_id
		on lo_firestore_id.firestore_id =  l.external_id
			and lo_firestore_id.firestore_id is not null
union all
	select
		lo_lead_id.*
	from lead l
	join
		public.lead_origin lo_lead_id
		on lo_lead_id.id_lead =  l.id
			and lo_lead_id.id_lead is not null
),
t_rn as (
select
	*,
	row_number() over (partition by id_lead order by rule_num desc) as lead_rn
from
	t_union
)
select
	id_lead,
	REPLACE(u_initial_utm_campaign, '–', '-') as tracking_campaign,
	u_initial_utm_medium as tracking_medium,
	u_initial_utm_source as tracking_source,
	u_initial_utm_content as tracking_content,
	u_initial_utm_term as tracking_term,
	u_platform as tracking_platform,
	region as tracking_region,
	city as tracking_city
from t_rn
where id_lead is not null and lead_rn = 1