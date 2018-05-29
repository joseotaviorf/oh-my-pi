with i_full as
(
SELECT 
	DATE(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS'))  AS dt,
	t_out.dadosagente_id,
    t_out.regiao_id,
    aux."Nossa nomenclatura"
FROM
	public.agent_region_hist t_out
LEFT join
	files.aux_regiao aux ON aux.id = t_out.regiao_id
WHERE
	TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS') BETWEEN dt_start AND dt_end
ORDER BY 2, 4 -- SPO 07, SPO 02 para o #6
)
, i_group as
(select
	i_full.dt,
	i_full.dadosagente_id,
	-- i.regiao_id,
	i_full."Nossa nomenclatura",
	count(i_full."Nossa nomenclatura") as times,
	rank() over (partition by i_full.dadosagente_id order by count(i_full."Nossa nomenclatura") DESC, i_full."Nossa nomenclatura" asc) ranking
from i_full
	group by
	i_full.dt,
	i_full.dadosagente_id,
	i_full."Nossa nomenclatura")
select
	g.dt,
	g.dadosagente_id,
	list.regions,
	g."Nossa nomenclatura" as area,
	(
	select r2."Nossa nomenclatura"
		from i_group r2
	where r2.dadosagente_id = g.dadosagente_id
			and r2.dt = g.dt
			and r2.ranking = 2
			and r2.times = g.times
	 ) as secondary_area
from i_group g
left join
	(select
		arh.dt,
		arh.dadosagente_id,
	    array_agg(arh.regiao_id order by arh.regiao_id) as regions
	 from
	 	i_full arh
	 group by
	 	arh.dt,
		arh.dadosagente_id
	) list
on list.dt = g.dt and list.dadosagente_id = g.dadosagente_id
where ranking = 1;