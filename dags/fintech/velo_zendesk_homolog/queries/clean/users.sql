WITH dedup_users AS (
    SELECT
        *
    FROM
        datalake_velo_zendesk_homolog_raw.users
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
)
SELECT
    usr.id AS id_user,
    usr.active AS is_active,
    usr.alias,
    usr.details,
    usr.email,
    usr.phone,
    usr.name,
    usr.notes,
    usr.url AS url_user,
    usr.chat_only,
    usr.custom_role_id AS id_custom_role,
    usr.default_group_id AS id_default_group,
    usr.external_id AS id_external,
    usr.locale,
    usr.locale_id AS id_locale,
    usr.moderator AS is_moderator,
    usr.only_private_comments AS is_only_private_comments,
    usr.organization_id AS id_organization,
    usr.permanently_deleted AS is_permanently_deleted,
    usr.report_csv AS is_report_csv,
    usr.restricted_agent AS is_restricted_agent,
    usr.role,
    usr.role_type,
    usr.shared AS is_shared,
    usr.shared_agent AS is_shared_agent,
    usr.shared_phone_number AS is_shared_phone_number,
    usr.signature,
    usr.suspended AS is_suspended,
    usr.tags,
    usr.ticket_restriction,
    usr.time_zone,
    usr.two_factor_auth_enabled AS is_two_factor_auth_enabled,
    usr.user_fields,
    usr.verified AS is_verified,
    usr.dt AS dt_extracted,
    CAST(usr.last_login_at AS TIMESTAMP) AS ts_last_login,
    CAST(usr.created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(usr.created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(usr.updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(usr.updated_at AS DATE)) AS year,
    MONTH(CAST(usr.updated_at AS DATE)) AS month,
    DAY(CAST(usr.updated_at AS DATE)) AS day
FROM
    dedup_users usr
