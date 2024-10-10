SELECT
    id as id_image,
    nome as name,
    principal as is_principal,
    imovel_id as id_house,
    legenda as subtitle,
    ordem as sequence,
    atualizadoEm as ts_updated,
    criadoEm as ts_created
from datalake_ebdb_test_raw.imagem
