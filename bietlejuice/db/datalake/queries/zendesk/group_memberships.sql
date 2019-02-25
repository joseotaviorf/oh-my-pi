select
    t.url,
    t.id,
    t.user_id,
    t.group_id,
    t.default,
    t.created_at,
    t.updated_at
from datalake_raw.zendesk_group_memberships t
__WHERE_CLAUSE__