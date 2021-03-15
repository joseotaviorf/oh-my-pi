WITH stitch_data AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id, dt ORDER BY updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.users
    WHERE
        dt = '{year}-{month}-{day}'
)
SELECT
    id AS id_user,
    active AS is_active,
    alias,
    details,
    email,
    phone,
    name,
    notes,
    url AS url_user,
    chat_only,
    custom_role_id AS id_custom_role,
    default_group_id AS id_default_group,
    external_id AS id_external,
    locale,
    locale_id AS id_locale,
    moderator AS is_moderator,
    only_private_comments AS is_only_private_comments,
    organization_id AS id_organization,
    permanently_deleted AS is_permanently_deleted,
    report_csv AS is_report_csv,
    restricted_agent AS is_restricted_agent,
    role,
    role_type,
    shared AS is_shared,
    shared_agent AS is_shared_agent,
    shared_phone_number AS is_shared_phone_number,
    signature,
    suspended AS is_suspended,
    tags,
    ticket_restriction,
    time_zone,
    two_factor_auth_enabled AS is_two_factor_auth_enabled,
    user_fields,
    verified AS is_verified,
    dt AS dt_extracted,
    CAST(last_login_at AS TIMESTAMP) AS ts_last_login,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
