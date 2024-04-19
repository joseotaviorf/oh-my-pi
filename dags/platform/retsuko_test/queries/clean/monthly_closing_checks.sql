select 
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    checks,
    accrual_year_month,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated
from
    datalake_retsuko_test_raw.monthly_closing_checks
