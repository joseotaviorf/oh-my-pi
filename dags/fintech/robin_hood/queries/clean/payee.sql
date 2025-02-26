select
    id,
    external_id as id_external,
    external_agent_id as id_external_agent,
    external_affiliate_id as id_external_affiliate,
    external_photographer_id as id_external_photographer,
    external_salesman_id as id_external_salesman,
    name,
    email,
    document_number,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated
from
    datalake_robin_hood_raw.payee
