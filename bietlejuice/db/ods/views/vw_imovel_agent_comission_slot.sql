--drop view if exists vw_imovel_agent_comission_slot;
--create or replace view vw_imovel_agent_comission_slot as
with published as
(
  select
    date_part('month', h.date) as period_month,
    date_part('year', h.date) as period_year,
  	hou.id,
    p.version,
    hou.regiao_id,
	count(distinct h.date) as qt_days_published
  from
    house hou
  inner join
    imovel_status_full_history h
    on h.id = hou.id
    and h.status_history = 'publicado'
    and h.last_position_date_flag
    
  inner join
	property_listing p
	on p.id = h.id
	and h.date between coalesce(p.min_version_time, '1900-01-01') and coalesce(p.max_version_time, now()) 

  group by
    date_part('month', h.date),
    date_part('year', h.date),
  	hou.id,
    p.version,
    hou.regiao_id
)
select
  date_part('month', c."Period") as month,
  date_part('year', c."Period") as year,
  u.id as id_user,
  r.regiao_id as id_region,
  i.id as id_property,
  i.version,
  c."Compensation"::decimal(14,4) as total_comission_slot,
  i.qt_days_published,
  sum(i.qt_days_published)
  	over (partition by
    	date_part('year', c."Period"),
        date_part('month', c."Period"),
        u.id
        -- ,i.version
      ) as qt_total_days_published,
  c."Compensation"::decimal(14,4)
  	/ sum(i.qt_days_published)
  		over (partition by
          date_part('year', c."Period"),
          date_part('month', c."Period"),
          u.id
          -- ,i.version
      	)
    * i.qt_days_published
  as comission_per_slot

--  cc."Amount earned" as comission_contract,

from
  usuario u
inner join
  files.agent_comission_hourly c
  on c.email = u.email
left join
  vw_agent_region r
  on r.agente_id = u.dados_agente_id
  and date_part('month', c."Period") = r.month
  and date_part('year', c."Period") = r.year
left join
  published i
  on i.regiao_id = r.regiao_id
  and date_part('month', c."Period") = i.period_month
  and date_part('year', c."Period") = i.period_year
-- where i.id = 892763559
-- where
--   u.email = 'fernando.rosmaninho@agentes.quintoandar.com.br'
  -- and date_part('month', c."Period") = 12
  -- and date_part('year', c."Period") = 2016
order by
  1,
  2,
  i.id;
