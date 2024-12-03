select
    id,
    user_id as id_user,
    tenant_flow,
    created_at as ts_created,
    updated_at as ts_updated
from
    datalake_docx_raw.user_tenant_flow
