select
    r.id AS id,
    r.criadaEm AS criadaEm,
    r.atualizadoEm AS atualizadoEm,
    r.nivel AS nivel,
    r.nome AS nome,
    mr.id AS macroId,
    mr.nome AS macroNome,
    c.id AS cidadeId,
    c.nome AS cidadeNome,
    now() as dt_timestamp
from
    Regiao r
left join Regiao mr on
    mr.id = r.regiaoPai_id
left join Regiao c on
    c.id = mr.regiaoPai_id
where
    r.nivel in ('SubRegiao', 'Cidade')
