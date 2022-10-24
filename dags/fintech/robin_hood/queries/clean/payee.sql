select
    id,
    external_id as id_external,
    external_agent_id as id_external_agent,
    external_affiliate_id as id_external_affiliate,
    external_photographer_id as id_external_photographer,
    external_salesman_id as id_external_salesman,
    sha2(name,256) as name,
    sha2(email,256) as email,
    sha2(document_number,256) as document_number,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated
from
    datalake_robin_hood_raw.payee