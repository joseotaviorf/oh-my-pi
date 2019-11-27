select
  a.id,
  a.imovel_id as id_house,
  a.authorization_id as id_authorization,
  a.restriction_id as id_restriction,
  a.type_id as id_type,
  a.occupant_id as id_occupant,
  a.password,
  a.description,
  a.lockeraddress as locker_address,
  a.additionalinfo as additional_info,
  a.criadoem as ts_created,
  a.atualizadoem as ts_updated,
  a.vacanton as ts_vacant_on
from datalake_ebdb_raw.AccessType a
