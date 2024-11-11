select
    id,
    payee_id as id_payee,
    name,
    document_number,
    bank_code,
    bank_name,
    account_type,
    agency_number,
    account_number,
    timestamp(created_at) as ts_created,
    timestamp(disabled_at) as ts_disabled
from
    datalake_robin_hood_raw.financial_data
