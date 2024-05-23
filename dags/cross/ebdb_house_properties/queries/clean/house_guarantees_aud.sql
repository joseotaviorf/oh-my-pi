select
   Imovel_id as id_house,
   garantias as guarantee_type,
   REV as rev,
   rEVTYPE as rev_type
from
   datalake_ebdb_raw.imovel_garantias_aud