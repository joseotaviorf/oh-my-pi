with
status_reason as (
select
    im.id as id_house,
    im.status,
    im.suspensionreason,
    im.unpublishedreason,
    case
	    when ((im.suspensionreason is not null or im.suspensionreason != '') and im.status = 'suspenso') then im.suspensionreason
	    when ((im.unpublishedreason is not null or im.unpublishedreason != '') and im.status = 'despublicado') then im.unpublishedreason
	    else 'unknown'
		end status_reason,
    rev.motivo as status_reason_2,
    date(timestamp 'epoch' + (cast(rev.timestamp as bigint)/1000)* interval '1 second') as date_change_suspension_reason--,
    --row_number() over (partition by im.id, im.status, status_reason order by date_change_suspension_reason) as rn
from datalake_raw.ebdb_imovel_aud im
join datalake_raw.ebdb_usuariorevisionentity rev on im.rev=rev.id
where
	(suspensionreason_mod = 1 and im.status = 'suspenso')
	or (unpublishedreason_mod = 1 and im.status = 'despublicado')
	--im.suspensionreason is not null then im.suspensionreason
	 --   when im.unpublishedreason is not null then im.unpublishedreason
),
aux_query as
(select
	fh.sk_house,
	fh.sk_region,
	fh.status_history,
	sr.status_reason,
	sr.status_reason_2,
	fh.sk_min_version_status_date,
	fh.sk_min_status_date,
	fh.sk_max_status_date,
	fh.dt_timestamp,
	row_number() over (partition by hl.id_house, fh.status_history, sr.status,	fh.sk_min_status_date order by hl.id_house) as rn
from fact_house_status fh
left join dim_house_listing hl
	on fh.sk_house = hl.sk_house_listing
left join status_reason as sr
	on sr.id_house = hl.id_house
	and fh.status_history = sr.status
	and fh.status_history in ('despublicado', 'suspenso')
	and sr.status in ('despublicado', 'suspenso')
	and sr.date_change_suspension_reason = date(fh.sk_min_status_date)
where
	hl.ts_publication >= '2018-01-01'
)
select
	sk_house,
	sk_region,
	status_history,
	status_reason,
	status_reason_2 as status_reason_motive,
	sk_min_version_status_date,
	sk_min_status_date,
	sk_max_status_date,
	dt_timestamp
from aux_query
where rn = 1