select -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
   bt.id as sk_bank_transaction,
   cast(bt.id_account as integer) as sk_bank_account,
   coalesce(u.id, -1) as sk_user_recipient,
   cast(coalesce(b.id, -1) as integer) as sk_bank,
   cast(date_format(bt.ts_transaction, "yyyyMMdd") as bigint) as sk_transaction,
   bt.id_house,
   cast(bt.value as decimal(22,2)) as value,
   bt.type,
   bt.ts_transaction as ts_transaction,
   bt.ts_updated,
   bt.ts_created,
   now() as ts_load
from datalake_ebdb_clean.account_transaction bt
left join datalake_ebdb_clean.user u on bt.id_account = u.id_account
left join datalake_ebdb_clean.bank b on b.id = u.id_bank
