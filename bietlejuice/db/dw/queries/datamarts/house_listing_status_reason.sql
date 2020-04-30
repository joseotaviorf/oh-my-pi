with
status_reason as (
select
    im.id_house,
    im.status,
    im.suspension_reason,
    im.unpublished_reason,
    case
	    when ((im.suspension_reason is not null or im.suspension_reason != '') and im.status = 'suspenso') then im.suspension_reason
	    when ((im.unpublished_reason is not null or im.unpublished_reason != '') and im.status = 'despublicado') then im.unpublished_reason
	    else 'unknown'
		end status_reason,
    rev.reason as status_reason_2,
    date(timestamp 'epoch' + (cast(rev.ts_revision as bigint)/1000)* interval '1 second') as date_change_suspension_reason
from datalake_ebdb_clean_prod.house_aud im
join datalake_ebdb_clean_prod.user_revision_entity rev on im.rev=rev.id
where
	(mod_suspension_reason = true and im.status = 'suspenso')
	or (mod_unpublished_reason = true and im.status = 'despublicado')
),
aux_query as
(select
	fh.sk_house_listing,
	fh.sk_region,
	fh.status_history,
	sr.status_reason,
	sr.status_reason_2,
	fh.sk_status_start_date,
	fh.sk_status_end_date,
	row_number() over (partition by hl.id_house, fh.status_history, sr.status, fh.sk_status_start_date order by hl.id_house) as rn
from fact_house_listing_status fh
left join dim_house_listing hl
	on fh.sk_house_listing = hl.sk_house_listing
left join status_reason as sr
	on sr.id_house = hl.id_house
	and fh.status_history = sr.status
	and fh.status_history in ('despublicado', 'suspenso')
	and sr.status in ('despublicado', 'suspenso')
	and sr.date_change_suspension_reason = date(fh.sk_status_start_date)
where
	hl.ts_publication >= '2018-01-01'
)
select
	sk_house_listing,
	sk_region,
	status_history,
	status_reason,
	status_reason_2 as status_reason_motive,
	sk_status_start_date,
	sk_status_end_date,
  	current_timestamp as ts_load
from aux_query
where rn = 1
;
