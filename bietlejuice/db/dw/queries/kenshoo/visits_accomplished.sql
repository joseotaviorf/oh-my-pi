with users_with_visits_last7d as (
	select distinct
	bk.id_visitor,
	bk.id_property,
	bk.visit_follow_up,
	bk.dt_scheduling::date as dt_scheduling,
	dr.city_group,
	u.email,
	replace(u.telefone_principal, '+', '') as phone
	from dim_booking bk
	join dim_user u on u.id = bk.id_visitor
	join dim_house_listing dhl on dhl.id_house = bk.id_property
	join fact_house_listings fhl on fhl.sk_house_listing = dhl.sk_house_listing
	join dim_region dr on dr.sk_region = fhl.sk_region
	where bk.type = 'Visita'
	and bk.visit_follow_up in ('VaiNegociar', 'VisitouSozinho', 'Talvez')
	and bk.dt_scheduling between dateadd(day, -7, date('{dt}')) and date('{dt}')
)
select distinct
city_group,
f_sha256(email) as email,
f_sha256(phone) as phone
from users_with_visits_last7d;