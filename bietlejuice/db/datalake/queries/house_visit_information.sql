with visit_information as
(
	select
	distinct
		id_house,
		trim(visit_information) as visit_information,
		FROM_UNIXTIME(ure.ts_revision/1000) as dt,
		case
			when rev_type=0 then 'add'
			when rev_type=2 then 'delete'
			else 'mod'
		end as rev_type
	from
		datalake_ebdb_clean_prod.house_visit_information_aud hvia
	left join
		datalake_ebdb_clean_prod.user_revision_entity ure
	on hvia.rev = ure.id
),
ranked_info as (
	select
		*,
		row_number() over (partition by id_house,visit_information order by dt) as row_id,
		rank() over (
			partition by id_house,visit_information,rev_type
			order by dt
		) as ranked
	from visit_information
),
joined as
(
	select
		r1.id_house,
		r1.visit_information,
		r1.ranked,
		r1.row_id as row1,
		r2.row_id as row2,
		r1.rev_type as rev1,
		r2.rev_type as rev2,
		case when r1.rev_type='add' then r1.dt else r2.dt end as dt_added,
		case when r1.rev_type='delete' then r1.dt else r2.dt end as dt_deleted
	from
		ranked_info r1
	left join
		ranked_info r2
		on r1.id_house = r2.id_house
		and r1.visit_information = r2.visit_information
		and r1.ranked = r2.ranked
		and r1.row_id < r2.row_id
)
select
	j1.id_house as imovel_id,
	j1.visit_information as informacoes_visita,
	j1.dt_added,
	j1.dt_deleted
from
	joined j1
left join
	joined j2
	on j1.id_house = j2.id_house
	and j1.visit_information = j2.visit_information
	and j1.row1 = j2.row2
where j2.id_house is null