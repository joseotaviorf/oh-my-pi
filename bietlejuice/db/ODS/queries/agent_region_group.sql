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
	and TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS') > TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS')  -- limit date, where aud started to be implemented
ORDER BY 2, 4
)
, i_union as
(
select
	*
 from i_full
union all
select distinct
	ag.available_date as dt,
	us.dados_agente_id as dadosagente_id,
	region_id as regiao_id,
	aux."Nossa nomenclatura"
from
	public.agents_schedule ag
left join public.usuario us
	on us.id = ag.agent_user_id
left join files.aux_regiao aux
	ON aux.id = ag.region_id
where
	ag.region_id is not null
	and us.dados_agente_id is not null
	and	ag.available_date = date(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS'))
	and date(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS')) <= date(TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS'))  -- limit date, where aud started to be implemented
)
, i_group as
(select
	i_union.dt,
	i_union.dadosagente_id,
	-- i.regiao_id,
	i_union."Nossa nomenclatura",
	count(i_union."Nossa nomenclatura") as times,
	rank() over (partition by i_union.dadosagente_id order by count(i_union."Nossa nomenclatura") DESC, i_union."Nossa nomenclatura" asc) ranking
from i_union
	group by
	i_union.dt,
	i_union.dadosagente_id,
	i_union."Nossa nomenclatura")
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
	 	i_union arh
	 group by
	 	arh.dt,
		arh.dadosagente_id
	) list
on list.dt = g.dt and list.dadosagente_id = g.dadosagente_id
where ranking = 1;