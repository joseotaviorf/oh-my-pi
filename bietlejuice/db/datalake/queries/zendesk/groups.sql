select
    t.url,
    t.id,
    t.name,
    t.deleted,
    t.created_at,
    t.updated_at
from datalake_raw.zendesk_groups t
__WHERE_CLAUSE__