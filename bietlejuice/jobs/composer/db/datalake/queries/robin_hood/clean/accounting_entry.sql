select
    id, 
    external_id as id_external,
    source_id as id_source,
    description,
    accrual_year_month,
    source_bill_item,
    payee_id as id_payee,
    due_amount,
    timestamp(created_at) as ts_created,
    locale,
    cost_center_code,
    date(occurrence_date) as dt_occurrence
from
    datalake_robin_hood_raw.accounting_entry