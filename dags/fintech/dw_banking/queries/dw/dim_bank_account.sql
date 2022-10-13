select
  u.id_account as sk_bank_account,
  u.id_account as id_bank_account,
  u.bank_account as account_number,
  u.bank_account_type as account_type,
  u.bank_agency as agency_number,
  a.ts_updated,
  a.ts_created,
  now() as ts_load
from datalake_ebdb_clean.user u
join datalake_ebdb_clean.account a
on u.id_account = a.id
