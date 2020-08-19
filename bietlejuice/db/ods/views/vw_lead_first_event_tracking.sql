--drop view if exists vw_lead_first_event_tracking;
--create view vw_lead_first_event_tracking as
with t_union as (
	select
		lo_external_id.*,
		l.id as id_from_lead
	from lead l
	join
		public.lead_origin lo_external_id
		on lo_external_id.e_formfield_lead_uuid =  l.external_id
			and lo_external_id.e_formfield_lead_uuid is not null
union all
	select
		lo_firestore_id.*,
		l.id as id_from_lead
	from lead l
	join
		public.lead_origin lo_firestore_id
		on lo_firestore_id.firestore_id =  l.external_id
			and lo_firestore_id.firestore_id is not null
union all
	select
		lo_lead_id.*,
		l.id as id_from_lead
	from lead l
	join
		public.lead_origin lo_lead_id
		on lo_lead_id.id_lead =  l.id
			and lo_lead_id.id_lead is not null
),
t_rn as (
select
	*,
	row_number() over (partition by id_from_lead order by rule_num desc) as lead_rn
from
	t_union
)
select
	id_from_lead as id_lead,
	replace_not_latin_chars(up_utm_campaign) as tracking_campaign,
	replace_not_latin_chars(up_utm_medium) as tracking_medium,
	replace_not_latin_chars(up_utm_source) as tracking_source,
	replace_not_latin_chars(up_utm_content) as tracking_content,
	replace_not_latin_chars(up_utm_term) as tracking_term,
	replace_not_latin_chars(up_platform) as tracking_platform,
	replace_not_latin_chars(up_referring_domain) as tracking_referring_domain,
	replace_not_latin_chars(region) as tracking_region,
	replace_not_latin_chars(city) as tracking_city
from t_rn
where id_from_lead is not null and lead_rn = 1