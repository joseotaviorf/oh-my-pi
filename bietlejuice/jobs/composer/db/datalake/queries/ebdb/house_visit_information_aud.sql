select
    rev,
    imovel_id as id_house,
    informacoesvisita as visit_information,
    revtype as rev_type
from datalake_ebdb_raw.Imovel_InformacoesVisita_Aud