select
    id,
    agent_id as id_agent,
    user_id as id_user,
    listing_id as id_listing,
    status,
    agent_comment,
    created_at as ts_created,
    updated_at as ts_updated
from
    datalake_ebdb_raw.agentsupport