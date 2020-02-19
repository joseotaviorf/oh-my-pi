select
  id,
  estado as state,
  cidade as city,
  logradouro as house_address_street,
  bairro as neighborhood,
  cep as zip_code,
  tpLogradouro as house_address_street_type,
  atualizadoEm as ts_updated,
  criadoEm as ts_created
from datalake_ebdb_raw.cep
