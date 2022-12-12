WITH
login_created AS (
    SELECT DISTINCT
        ts_event as ts_login_created,
        id_user
    FROM
        datalake_amplitude_clean.events
    WHERE
        event_type = 'login_user_created'
),
sale_users AS (
  SELECT
    id_user,
    DATE(ts_event) AS dt_event,
    COUNT(DISTINCT CASE WHEN LOWER(get_json_object(event_properties, '$.business_context')) = 'sale' THEN uuid END)
      / CAST(COUNT(DISTINCT uuid) AS DOUBLE) AS prop_sale,
    AVG(
        COUNT(DISTINCT CASE WHEN LOWER(get_json_object(event_properties, '$.business_context')) = 'sale' THEN uuid END)
            / CAST(COUNT(DISTINCT uuid) AS DOUBLE)
        ) OVER(PARTITION BY id_user ORDER BY DATE(ts_event) ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS prop_sale_7d
  FROM
    datalake_amplitude_clean.events
  WHERE
    id_app = 170698
    AND get_json_object(event_properties, '$.business_context') IS NOT NULL
    AND id_user IS NOT NULL
    AND year >= 2021
    AND DATE(ts_event) >= DATE('2021-05-01')
  GROUP BY id_user, DATE(ts_event)
),
combo_events AS (
    SELECT
        evt.ts_event,
        COALESCE(lc.ts_login_created, DATE('2000-01-01')) AS ts_login_created,
        GREATEST(evt.ts_event, DATE_ADD(COALESCE(lc.ts_login_created, DATE('2000-01-01')), 7)) AS ts_combo_triggered,
        evt.id_user,
        evt.event_type,
        fl.id_region AS sk_region,
        fl.id_user AS sk_owner,
        get_json_object(evt.event_properties, '$.house_id') AS id_house,
        event_type || '_' || get_json_object(evt.event_properties, '$.house_id') AS sk_event,
        MIN(ts_event) OVER(PARTITION BY evt.id_user) AS ts_first_combo_event
    FROM
        datalake_amplitude_clean.events AS evt
        LEFT JOIN datalake_ebdb_clean.house fl
            ON fl.id = CAST(get_json_object(evt.event_properties, '$.house_id') AS BIGINT)
        JOIN sale_users AS su
            ON evt.id_user = su.id_user
            AND DATE(evt.ts_event) = su.dt_event
            AND ((prop_sale_7d > 0.5 AND DATE(evt.ts_event) <= DATE('2021-11-11'))
                 OR (prop_sale_7d > 0.6 AND DATE(evt.ts_event) > DATE('2021-11-11')))
        LEFT JOIN login_created AS lc
            ON lc.id_user = evt.id_user
    WHERE TRUE
        AND evt.id_app = 170698
        AND NULLIF(TRIM(get_json_object(evt.event_properties, '$.house_id')), '') IS NOT NULL
        AND NULLIF(evt.id_user, '') IS NOT NULL
        AND DATE(evt.ts_event) >= DATE('2021-06-01')
        AND year >= 2021
        AND event_type IN ('listing_tab_clicked', 'unavailable_listing_viewed', 'share_listing',
                           'mtgsimulator_startsimulation_clicked', 'listing_favorite_set', 'homes_subscription_confirmed')
        AND LOWER(get_json_object(evt.event_properties, '$.business_context')) = 'sale'
        AND CAST(evt.id_user AS BIGINT) != fl.id_user
),
clients_scm as (
    select
        id as id_client,
        '+55'||phone_number as phone_number,
        ts_created
    from datalake_casa_mineira_crm_clean.contact
),
base AS (
     SELECT DISTINCT
        ce.id_user || '_' || ce.id_house AS id_combo_event,
        ce.id_user,
        ce.id_house,
        CAST(ce.sk_owner AS STRING),
        CAST(ce.sk_region AS STRING),
        ce.event_type,
        du.nome AS user_full_name,
        du.telefone_principal AS phone,
        ce.ts_combo_triggered,
        cm.ts_created as ts_secretaria_client_created,
        DATE(ce.ts_combo_triggered) AS dt_combo_triggered
     from combo_events AS ce
        JOIN dw_public.dim_user AS du
            ON CAST(ce.id_user AS INTEGER) = du.sk_user
        LEFT JOIN clients_scm AS cm
            ON cm.phone_number = du.telefone_principal
     WHERE
        ts_event = ts_first_combo_event
        AND ce.ts_combo_triggered >= date('2021-07-01')
        AND du.telefone_principal IS NOT NULL
        AND DATE(ce.ts_combo_triggered) < CURRENT_DATE
        AND NOT COALESCE(du.is_sale_agent, FALSE)
        AND NOT COALESCE(du.is_rent_agent, FALSE)
)
SELECT
    *,
    NOW() AS ts_load
FROM base
