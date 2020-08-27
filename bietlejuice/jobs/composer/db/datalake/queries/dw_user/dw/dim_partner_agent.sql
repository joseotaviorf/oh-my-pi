select
    id as sk_partner_agent,
    id as id_partner_agent,
    id_user,
    id_partner,
    status,
    type,
    ts_created,
    ts_updated,
    now() as ts_load
from datalake_ebdb_clean.partner_agent
