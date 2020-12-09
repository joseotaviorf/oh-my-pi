WITH house_listing_context AS (
    SELECT
        h.id_user,
        MAX(is_rent_context) AS is_for_rent,
        MAX(is_sale_context) AS is_for_sale,
        MIN(h.dt_creation) AS dt_first_creation
    FROM
        datalake_ebdb_listing.listing_business_context AS lbc
    JOIN
        datalake_ebdb_listing.house AS h
            ON lbc.id_house = h.id
    GROUP BY 
        1
),
user_contact_preferences AS (
    SELECT DISTINCT
        id_user,
        FIRST_VALUE(is_receiving_sms) OVER (PARTITION BY id_user ORDER BY ts_created DESC) AS has_sms_notifications_enabled,
        FIRST_VALUE(is_receiving_whatsapp) OVER (PARTITION BY id_user ORDER BY ts_created DESC) AS has_whatsapp_notifications_enabled
    FROM
        datalake_ebdb_clean.user_preferences
)
SELECT
    hlc.id_user AS sk_listing_owner,
    u.name,
    u.cpf AS personal_document,
    u.email,
    u.main_phone AS phone,
    u.address AS address_street,
    u.number AS address_number,
    u.complement AS address_complement,
    u.neighborhood AS address_neighborhood,
    u.city,
    u.uf,
    u.zip_code AS address_postal_code,
    pa.id_user IS NOT NULL AS is_b2b,
    hlc.is_for_rent AS has_rent_listings,
    hlc.is_for_sale AS has_sale_listings,
    ucp.has_sms_notifications_enabled AS has_sms_notifications_enabled,
    ucp.has_whatsapp_notifications_enabled AS has_whatsapp_notifications_enabled,
    u.dt_birth,
    u.ts_created AS ts_user_signed_up,
    hlc.dt_first_creation AS ts_first_house_created,
    NOW() AS ts_load
FROM
    datalake_ebdb_user.user AS u
JOIN
    house_listing_context AS hlc
        ON u.id = hlc.id_user
LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
        ON pa.id_user = u.id
LEFT JOIN
    user_contact_preferences AS ucp
        ON u.id = ucp.id_user