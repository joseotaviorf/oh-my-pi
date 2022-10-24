select
    id,
    payee_id as id_payee,
    related_account_id as id_related_account,
    related_account_type,
    source_id as id_source,
    timestamp(created_at) as ts_created,
    timestamp(disabled_at) as ts_disabled
from
    datalake_robin_hood_raw.payee_account