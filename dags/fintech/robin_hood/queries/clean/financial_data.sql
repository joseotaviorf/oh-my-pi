select
    id,
    payee_id as id_payee,
    sha2(name,256) as name,
    sha2(document_number,256) as document_number,
    bank_code,
    bank_name,
    sha2(account_type,256) as account_type,
    sha2(agency_number,256) as agency_number,
    sha2(account_number,256) as account_number,
    timestamp(created_at) as ts_created,
    timestamp(disabled_at) as ts_disabled
from
    datalake_robin_hood_raw.financial_data
