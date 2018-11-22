drop view if exists vw_agent_region;
create view vw_agent_region as
select
    date_part('year', coalesce(b."criadoEm", b.data)) as year,
    date_part('month', coalesce(b."criadoEm", b.data)) as month,
    h.regiao_id,
    b.agente_id
from
	booking b
inner join
	house h
    on h.id = b.imovel_id
where
	coalesce(b."criadoEm", b.data) < date_trunc('month', current_date)
    and h.regiao_id is not null
    and b.agente_id is not null
group by
    date_part('year', coalesce(b."criadoEm", b.data)),
    date_part('month', coalesce(b."criadoEm", b.data)),
	h.regiao_id,
    b.agente_id

union all

select
	date_part('year', current_date) as year,
    date_part('month', current_date) as month,
    ar.regioes_id as regiao_id,
    ar."DadosAgente_id" as agente_id
from
	agent_region ar
order by
	1 desc,
    2 desc
;