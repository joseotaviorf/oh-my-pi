drop view if exists vw_fact_listing_status;
create view vw_fact_listing_status as
select
	a.id as sk_property,
	a.date::date as status_date,
    a.id,
	a.status,
    a.status_time as status_updated_time
from
	vw_imovel_status_history_position_by_day a;