select
    id,
    rating,
    complementaryinfo as complementary_info,
    atualizadoem as ts_updated,
    criadoem as ts_created
from
    datalake_ebdb_raw.RealEstateAgentRating