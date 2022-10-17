WITH distinct_customer_email AS (
    SELECT DISTINCT
        cci_e.id_user,
        cci_e.customer_contact as email,
        cci_e.cpf
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
    WHERE
        cci_e.channel = 'email'
),
distinct_customer_phone AS (
    SELECT DISTINCT
        cci_p.id_user,
        CASE
            WHEN cci_p.customer_contact NOT LIKE '+%' AND LENGTH(REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', '')) < 12
                THEN CONCAT('55', REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', ''))
                ELSE REGEXP_REPLACE(cci_p.customer_contact, '\\D|^0+', '')
        END AS phone,
        cci_p.cpf
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
    WHERE
        cci_p.channel  = 'phone'
)
SELECT
    COALESCE(dc_e.id_user, dc_p.id_user) AS id_user,
    COALESCE(dc_e.cpf, dc_p.cpf) AS id_personal_document,
    CAST(usr.id_user AS BIGINT) AS id_zendesk_user,
    CASE
        WHEN usr.phone NOT LIKE '+%' AND LENGTH(REGEXP_REPLACE(usr.phone, '\\D|^0+', '')) < 12
            THEN CONCAT('55', REGEXP_REPLACE(usr.phone, '\\D|^0+', ''))
            ELSE REGEXP_REPLACE(usr.phone, '\\D|^0+', '')
    END AS phone,
    usr.email,
    usr.is_active,
    usr.name,
    usr.url_user,
    usr.locale,
    usr.id_locale,
    usr.is_moderator,
    usr.is_only_private_comments,
    usr.id_organization,
    usr.is_permanently_deleted,
    usr.is_report_csv,
    usr.is_restricted_agent,
    usr.role,
    usr.role_type,
    usr.is_shared,
    usr.is_shared_agent,
    usr.is_shared_phone_number,
    usr.signature,
    usr.is_suspended,
    usr.tags,
    usr.ticket_restriction,
    usr.time_zone,
    usr.user_fields,
    usr.is_verified,
    usr.dt_extracted,
    usr.ts_last_login,
    usr.ts_created,
    usr.ts_created_local,
    usr.ts_updated
FROM
    datalake_zendesk_tickets_clean.users usr
LEFT JOIN
    distinct_customer_email dc_e
        ON dc_e.email = usr.email
LEFT JOIN
    distinct_customer_phone dc_p
        ON dc_p.phone = usr.phone
