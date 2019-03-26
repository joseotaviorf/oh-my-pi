select
    pr.id AS id,
    ST_ASText(pr.poligono) AS poligono,
    pr.regiao_id AS regiao_id,
    pr.atualizadoem as atualizadoEm,
    pr.criadoem as criadoEm,
    now() as dt_timestamp
from
    PoligonoRegiao pr
