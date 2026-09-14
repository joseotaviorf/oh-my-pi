WITH listing_page_view_users AS (
    SELECT
        tracking.id_user
    FROM
        datalake_cdp_clean.user_tracking AS tracking
    WHERE
        MAKE_DATE(tracking.year, tracking.month, tracking.day) >= DATE_SUB(CURRENT_DATE(), 30)
        AND tracking.id_user IS NOT NULL
        AND tracking.event_name = 'listing_page_viewed'
        AND GET_JSON_OBJECT(tracking.event_properties, '$.business_context') = 'rent'
    GROUP BY
        tracking.id_user
    HAVING
        COUNT(*) > 2
),
signed_tenants AS (
    SELECT DISTINCT
        contracts.id_tenant AS id_user
    FROM
        core_contract.contract AS contracts
    WHERE
        contracts.ts_signed >= DATE_SUB(CURRENT_DATE(), 30)
)
SELECT
    CAST(listing_viewers.id_user AS STRING) AS id_user,
    users.email AS email_address,
    users.uuid_person
FROM
    listing_page_view_users AS listing_viewers
INNER JOIN
    dw_public.dim_user AS users
    ON listing_viewers.id_user = users.sk_user
LEFT ANTI JOIN
    signed_tenants AS recently_signed
    ON listing_viewers.id_user = recently_signed.id_user
WHERE
    NULLIF(users.email, '') IS NOT NULL
    AND users.email NOT LIKE '%@corretores.quintoandar.com.br'
    AND (users.country_code = 'BR' OR users.country_code IS NULL)
