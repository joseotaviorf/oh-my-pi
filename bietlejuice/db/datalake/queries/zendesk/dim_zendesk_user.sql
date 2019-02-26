select
    t.id as sk_zendesk_user,
    t.url,
    t.name,
    t.email,
    t.phone,
    t.time_zone,
    t.shared_phone_number,
    t.locale,
    t.organization_id,
    t.verified,
    t.external_id,
    t.tags,
    t.role,
    t.active,
    t.default_group_id as group_id,
    t.last_login_at,
    t.created_at,
    t.updated_at
from datalake_clean.zendesk_users t
__WHERE_CLAUSE__