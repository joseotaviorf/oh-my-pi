select
    t.id,
    t.title,
    t.raw_title,
    case t.collapsed_for_agents when 'false' then '0' when 'true' then '1' end as collapsed_for_agents,
    case t.visible_in_portal when 'false' then '0' when 'true' then '1' end as visible_in_portal,
    t.description,
    case t.active when 'false' then '0' when 'true' then '1' end as active,
    t.raw_title_in_portal,
    t.created_at,
    t.type,
    t.raw_description,
    case t.required when 'false' then '0' when 'true' then '1' end as required,
    case t.editable_in_portal when 'false' then '0' when 'true' then '1' end as editable_in_portal,
    case t.required_in_portal when 'false' then '0' when 'true' then '1' end as required_in_portal,
    t.updated_at,
    t.system_field_options,
    case t.removable when 'false' then '0' when 'true' then '1' end as removable,
    t.regexp_for_validation,
    t.position,
    t.tag,
    t.title_in_portal
from datalake_raw.zendesk_ticket_fields_xplenty t
__WHERE_CLAUSE__