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
	g."Nossa nomenclatura" as area
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