drop view if exists vw_property_status_over_period;

CREATE VIEW public.vw_property_status_over_period 
as
select 
	 ((p.id || '00') || COALESCE(p.version, 1))::bigint AS sk_property,
	 p.id,
	 p.publication_date::date as pub_date,
	 p."version",
	 (i.date - p.publication_date::date)::varchar || ' days' as days,
	 i.date as date,
	 i.status_history as status
from 
	property_listing  p
inner join
	imovel_status_full_history i
	on i.id = p.id
	and i.date in (
		p.publication_date::date + interval '7' day, 
		p.publication_date::date + interval '14' day, 
		p.publication_date::date + interval '21' day,
		p.publication_date::date + interval '28' day,
		p.publication_date::date + interval '35' day,
		p.publication_date::date + interval '42' day,
		p.publication_date::date + interval '49' day,
		p.publication_date::date + interval '56' day
	)
;