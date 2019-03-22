select
    rp.id AS id,
    rp.poligono AS poligono,
    rp.regiao_id AS regiao_id,
    rp.atualizadoem as atualizadoEm,
    rp.criadoem as criadoEm,
    now() as dt_timestamp
from
    RegiaoPoligono rp
