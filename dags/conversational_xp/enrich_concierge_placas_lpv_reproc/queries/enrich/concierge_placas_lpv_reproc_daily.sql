WITH placas_sends AS (
    SELECT
        user_notif.id_user AS id_user_agent,
        DATE(user_notif.ts_sent) AS dt_envio,
        user_notif.ts_sent,
        GET_JSON_OBJECT(user_notif.payload, '$.templateVariables.2') AS id_house_raw,
        REGEXP_REPLACE(GET_JSON_OBJECT(user_notif.payload, '$.templateVariables.4'), '[^0-9]', '') AS lead_phone_digits,
        ROW_NUMBER() OVER (
            PARTITION BY
                user_notif.id_user,
                DATE(user_notif.ts_sent),
                GET_JSON_OBJECT(user_notif.payload, '$.templateVariables.4'),
                GET_JSON_OBJECT(user_notif.payload, '$.templateVariables.2')
            ORDER BY
                user_notif.ts_sent
        ) AS rn
    FROM
        datalake_jaiminho_clean.user_notifications AS user_notif
    WHERE
        user_notif.template = 'leads_placas_cr_v2'
        AND DATE(user_notif.ts_sent) >= DATE('{poc_start_date}')
        AND DATE(user_notif.ts_sent) <= DATE_SUB(CURRENT_DATE(), {days_maturity})
),
sale_agents AS (
    SELECT
        ebdb_user.id AS id_user_agent,
        agent_data.is_sale_agent
    FROM
        datalake_ebdb_user.user AS ebdb_user
    INNER JOIN
        datalake_ebdb_user.agent_data AS agent_data
        ON ebdb_user.id_agent = agent_data.id
    WHERE
        agent_data.is_sale_agent = TRUE
),
lead_users AS (
    SELECT
        REGEXP_REPLACE(cdp_users.phone_number, '[^0-9]', '') AS phone_digits,
        cdp_users.id_user,
        cdp_users.id_person,
        cdp_users.phone_number,
        ROW_NUMBER() OVER (
            PARTITION BY REGEXP_REPLACE(cdp_users.phone_number, '[^0-9]', '')
            ORDER BY cdp_users.id_user DESC
        ) AS rn_user
    FROM
        datalake_cdp.users AS cdp_users
    WHERE
        cdp_users.phone_number IS NOT NULL
),
eligible_sends AS (
    SELECT
        placas_sends.id_user_agent,
        placas_sends.dt_envio,
        TRY_CAST(placas_sends.id_house_raw AS BIGINT) AS id_house,
        lead_users.id_user,
        lead_users.id_person,
        lead_users.phone_number
    FROM
        placas_sends
    INNER JOIN
        sale_agents
        ON placas_sends.id_user_agent = sale_agents.id_user_agent
    INNER JOIN
        lead_users
        ON placas_sends.lead_phone_digits = lead_users.phone_digits
        AND lead_users.rn_user = 1
    WHERE
        placas_sends.rn = 1
        AND placas_sends.lead_phone_digits <> ''
),
agent_phones AS (
    SELECT
        ebdb_user.id AS id_user_agent,
        REGEXP_REPLACE(cdp_users.phone_number, '[^0-9]', '') AS agent_phone_digits
    FROM
        datalake_ebdb_user.user AS ebdb_user
    LEFT JOIN
        datalake_cdp.users AS cdp_users
        ON cdp_users.id_user = ebdb_user.id
),
filtered_agents AS (
    SELECT
        eligible_sends.*
    FROM
        eligible_sends
    LEFT JOIN
        agent_phones
        ON eligible_sends.id_user_agent = agent_phones.id_user_agent
    WHERE
        COALESCE(agent_phones.agent_phone_digits, '') NOT IN ('{excluded_agent_phone_1}', '{excluded_agent_phone_2}')
),
tqc_after AS (
    SELECT DISTINCT
        filtered_agents.id_user,
        filtered_agents.id_house,
        filtered_agents.dt_envio
    FROM
        filtered_agents
    INNER JOIN
        datalake_tqc_referral.unified_lead_referral_flow AS tqc
        ON tqc.id_user_agent = filtered_agents.id_user_agent
        AND DATE(tqc.ts_created) >= filtered_agents.dt_envio
        AND DATE(tqc.ts_created) >= DATE('{poc_start_date}')
        AND REGEXP_REPLACE(tqc.lead_phone, '[^0-9]', '') = REGEXP_REPLACE(filtered_agents.phone_number, '[^0-9]', '')
),
sale_vb_after AS (
    SELECT DISTINCT
        filtered_agents.id_user,
        filtered_agents.id_house,
        filtered_agents.dt_envio
    FROM
        filtered_agents
    INNER JOIN
        datalake_visit.visits AS sale_visit
        ON sale_visit.id_visitor = filtered_agents.id_user
        AND sale_visit.id_agent = filtered_agents.id_user_agent
        AND UPPER(sale_visit.business_context) = 'SALE'
        AND DATE(sale_visit.ts_created) >= filtered_agents.dt_envio
        AND DATE(sale_visit.ts_created) >= DATE('{poc_start_date}')
),
current_privacy_snapshot AS (
    SELECT
        id_person,
        is_concierge_privacy_suppressed
    FROM
        datalake_search.concierge_privacy_user
    WHERE
        year = YEAR(CURRENT_DATE())
        AND month = MONTH(CURRENT_DATE())
        AND day = DAY(CURRENT_DATE())
),
recent_lpv_trigger AS (
    SELECT DISTINCT
        id_user
    FROM
        datalake_jaiminho_clean.user_notifications
    WHERE
        (
            action = 'ConciergeSharedLpvAdsTrigger'
            OR template IN (
                'concierge_placas_agents_reproc_trigger',
                'concierge_placas_reply_sfmc'
            )
        )
        AND DATE(ts_sent) >= DATE_SUB(CURRENT_DATE(), {days_trigger_cooldown})
        AND id_user IS NOT NULL
),
house_on_sale AS (
    SELECT
        TRY_CAST(id AS BIGINT) AS id_house,
        city,
        neighborhood,
        sale_price
    FROM
        datalake_ebdb_clean.house
    WHERE
        sale_price > 0
),
lpv_ads_eligible_today AS (
    -- Cross-exclusion: users already eligible today for the Shared/Retargeting
    -- LPV-ads concierge use case, to avoid double-messaging the same user across
    -- both concierge programs on the same day (see enrich_concierge_lpv_ads).
    SELECT DISTINCT
        id_user
    FROM
        datalake_search.concierge_lpv_ads_daily
    WHERE
        year = YEAR(CURRENT_DATE())
        AND month = MONTH(CURRENT_DATE())
        AND day = DAY(CURRENT_DATE())
)
SELECT DISTINCT
    filtered_agents.id_user,
    filtered_agents.id_person,
    filtered_agents.id_house,
    'SALE' AS business_context,
    house_on_sale.city,
    house_on_sale.neighborhood AS region_name,
    house_on_sale.sale_price AS price_arred,
    CONCAT(
        'https://www.quintoandar.com.br/imovel/',
        CAST(filtered_agents.id_house AS STRING),
        '/comprar?utm_campaign=ZEBRA.sale.acq.nonorg.na.d.placas.na.whatsapp_fss&utm_source=plaquinhas_qrwhats&utm_term=t004'
    ) AS house_link,
    filtered_agents.dt_envio,
    CASE
        WHEN TRY_CAST(RIGHT(REGEXP_REPLACE(filtered_agents.phone_number, '[^0-9]', ''), 3) AS INT) <= 499 THEN 'Control'
        ELSE 'Test'
    END AS group_ab,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    filtered_agents
INNER JOIN
    house_on_sale
    ON filtered_agents.id_house = house_on_sale.id_house
LEFT JOIN
    tqc_after
    ON filtered_agents.id_user = tqc_after.id_user
    AND filtered_agents.id_house = tqc_after.id_house
    AND filtered_agents.dt_envio = tqc_after.dt_envio
LEFT JOIN
    sale_vb_after
    ON filtered_agents.id_user = sale_vb_after.id_user
    AND filtered_agents.id_house = sale_vb_after.id_house
    AND filtered_agents.dt_envio = sale_vb_after.dt_envio
LEFT JOIN
    current_privacy_snapshot
    ON filtered_agents.id_person = current_privacy_snapshot.id_person
LEFT JOIN
    recent_lpv_trigger
    ON filtered_agents.id_user = recent_lpv_trigger.id_user
LEFT JOIN
    lpv_ads_eligible_today
    ON filtered_agents.id_user = lpv_ads_eligible_today.id_user
WHERE
    tqc_after.id_user IS NULL
    AND sale_vb_after.id_user IS NULL
    AND COALESCE(
        current_privacy_snapshot.is_concierge_privacy_suppressed,
        FALSE
    ) = FALSE
    AND recent_lpv_trigger.id_user IS NULL
    AND lpv_ads_eligible_today.id_user IS NULL
