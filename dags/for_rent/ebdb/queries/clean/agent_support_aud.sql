select
    id,
    rev,
    revtype as rev_type,
    user_id as id_user,
    user_id_mod as mod_id_user,
    agent_id as id_agent,
    agent_id_mod as mod_id_agent,
    listing_id as id_listing,
    listing_id_mod as mod_id_listing,
    status,
    status_mod as mod_status,
    agent_comment,
    agent_comment_mod as mod_agent_comment
from
    datalake_ebdb_raw.agentsupport_aud