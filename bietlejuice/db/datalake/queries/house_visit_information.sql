with info_visita as
(
	select
	distinct
		cast(imovel_id as bigint) as imovel_id,
		trim(informacoesvisita) as informacoes_visita,
		cast(FROM_UNIXTIME(cast(ure."timestamp" as bigint)/1000) as timestamp) as dt,
--		coalesce(usuario_id, null) as usuario_id,
		case
			when revtype='0' then 'add'
			when revtype='2' then 'delete'
			else 'mod'
		end as revtype
	from
		datalake_clean.ebdb_informacoes_visita_aud iva
	left join
		datalake_clean.ebdb_usuario_revision_entity ure
	on iva.REV = ure.id
),
ranked_info as (
	select
		*,
		row_number() over (partition by imovel_id,informacoes_visita order by dt) as row_id,
		rank() over (
			partition by imovel_id,informacoes_visita,revtype
			order by dt
		) as ranked
	from info_visita
),
joined as
(
	select
		r1.imovel_id,
		r1.informacoes_visita,
		r1.ranked,
		r1.row_id as row1,
		r2.row_id as row2,
		r1.revtype as rev1,
		r2.revtype as rev2,
		case when r1.revtype='add' then r1.dt else r2.dt end as dt_added,
		case when r1.revtype='delete' then r1.dt else r2.dt end as dt_deleted
	from
		ranked_info r1
	left join
		ranked_info r2
		on r1.imovel_id = r2.imovel_id
		and r1.informacoes_visita = r2.informacoes_visita
		and r1.ranked = r2.ranked
		and r1.row_id < r2.row_id
)
select
	j1.imovel_id,
	j1.informacoes_visita,
	j1.dt_added,
	j1.dt_deleted
from
	joined j1
left join
	joined j2
	on j1.imovel_id = j2.imovel_id
	and j1.informacoes_visita = j2.informacoes_visita
	and j1.row1 = j2.row2
where j2.imovel_id is null