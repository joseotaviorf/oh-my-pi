with analysis_date as (
select
oa.id,
min(cast(from_unixtime(cast(ure.timestamp as double) / 1000) as timestamp)) as _date
from datalake_raw.ebdb_offer_aud oa
join datalake_raw.ebdb_usuariorevisionentity ure
on oa.rev = ure.id
where
	oa.status_MOD = '1'
	and oa.status in ('Aprovada', 'Rejeitada')
group by 1
),
rent_values as
(
select
	godfatherid,
	originalrent,
	max(case when turn = 'Owner' then rent end) as last_rent_value_offered_by_tenant,
	max(case when turn = 'Tenant' then rent end) as last_rent_value_offered_by_owner
from
(
select
	distinct
	eoa.godfatherid,
	eoa.originalrent,
	first_value(rent) over (partition by eoa.godfatherid, eoa.turn) as rent,
	eoa.turn
from datalake_raw.ebdb_offer_aud eoa
)
group by 1, 2
)
select distinct
  eo.id,
  eo.atualizadoem,
  ad._date as analysis_date,
  eo.criadoem,
  eo.firestoreid,
  eo.godfatherid,
  eo.originalcondo,
  eo.originalhomeinsurance,
  eo.originaliptu,
  eo.originalrent,
  eo.rent,
  eo.status,
  eo.turn,
  eo.client_id,
  eo.house_id,
  eo.rentflow_id,
  eo.rejectionreason,
  eo.iteration,
  eo.expirationdate,
  go.type,
  go.first_sent_at,
  go.last_sent_at,
  gt.type as topic_type,
  rv.last_rent_value_offered_by_tenant,
  rv.last_rent_value_offered_by_owner
from datalake_raw.ebdb_offer eo
join datalake_raw.godfather_offer go
  on eo.godfatherid = go.id
left join datalake_raw.godfather_topic gt
  on gt.offer_id = go.id
left join analysis_date ad
  on ad.id = eo.id
left join rent_values rv
  on rv.godfatherid = eo.godfatherid
;