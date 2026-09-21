WITH agent_spine AS (
    SELECT
        agent.id_agent,
        agent.id_agent_data,
        agent.id_partner,
        agent.id_user,
        agent.uuid_company,
        agent.uuid_agent,
        agent.uuid_person,
        agent.creci,
        agent.creci_uf,
        agent.affiliation_type,
        agent.profile,
        agent.is_1p_partnership,
        agent.is_3p_partnership,
        agent.days_in_current_status,
        agent.ts_last_status_changed,
        agent.ts_created,
        EXPLODE(
            SEQUENCE(
                DATE(agent.ts_created),
                GREATEST(DATE(agent.ts_created), CURRENT_DATE),
                INTERVAL 1 DAY
            )
        ) AS dt_ref
    FROM
        datalake_agent_accreditation.agent AS agent
),
agent_date AS (
    SELECT
        MD5(CONCAT(agent.id_agent, agent.dt_ref)) AS id_agent_daily,
        agent.id_agent,
        MAX(agent.id_agent_data) AS id_agent_data,
        MAX(agent.id_partner) AS id_partner,
        MAX(agent.id_user) AS id_user,
        MAX(agent.uuid_company) AS uuid_company,
        MAX(agent.uuid_agent) AS uuid_agent,
        MAX(agent.uuid_person) AS uuid_person,
        MAX(agent.creci) AS creci,
        MAX(agent.creci_uf) AS creci_uf,
        MAX(agent.affiliation_type) AS affiliation_type,
        MAX(agent.profile) AS profile,
        MAX(agent.is_1p_partnership) AS is_1p_partnership,
        MAX(agent.is_3p_partnership) AS is_3p_partnership,
        MAX(agent.days_in_current_status) AS days_in_current_status,
        MAX(agent.ts_last_status_changed) AS ts_last_status_changed,
        MAX(agent.ts_created) AS ts_created,
        agent.dt_ref,
        YEAR(agent.dt_ref) AS year,
        MONTH(agent.dt_ref) AS month,
        DAY(agent.dt_ref) AS day
    FROM
        agent_spine AS agent
    WHERE
        agent.dt_ref BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        agent.id_agent,
        agent.dt_ref
),
activation_history AS (
    SELECT
        id_agent,
        id_capability,
        event_level,
        capability_type,
        event_type,
        ts_started,
        LEAD(ts_started) OVER(PARTITION BY id_agent, id_capability ORDER BY ts_started) AS ts_status_ended,
        DATE(ts_started) AS dt_started,
        DATE(ts_status_ended) AS dt_ended
    FROM
        datalake_agent_accreditation.agent_event_log
    WHERE
        event_type IN ('AGENT_CAPABILITY_DISABLED', 'AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED', 'AGENT_ACTIVATED', 'AGENT_INACTIVATED', 'AGENT_REACTIVATED')
),
segmentation_activation_history AS (
    SELECT DISTINCT
        segmented.id_agent,
        segmented.id_capability,
        segmented.event_type,
        segmented.event_level,
        segmented.capability_type,
        segmented.ts_started,
        segmented.dt_reference
    FROM (
        SELECT
            ah.id_agent,
            ah.id_capability,
            ah.event_type,
            ah.event_level,
            ah.capability_type,
            ah.ts_started,
            EXPLODE(
                SEQUENCE(
                    ah.dt_started,
                    GREATEST(
                        ah.dt_started,
                        COALESCE(ah.dt_ended - INTERVAL 1 DAY, CURRENT_DATE)
                    ),
                    INTERVAL 1 DAY
                )
            ) AS dt_reference
        FROM
            activation_history AS ah
    ) AS segmented
),
daily_status AS (
    SELECT
        ad.id_agent_daily,
        ad.id_agent,
        ad.id_agent_data,
        ad.id_partner,
        ad.id_user,
        MAX(ah.id_capability) FILTER(WHERE ah.capability_type = 'DEMAND_VISIT_MANAGEMENT') AS id_capability_demand_visit,
        ad.uuid_company,
        ad.uuid_agent,
        ad.uuid_person,
        ad.creci,
        ad.creci_uf,
        ad.affiliation_type,
        ad.profile,
        ad.is_1p_partnership,
        ad.is_3p_partnership,
        ad.ts_created,
        ad.dt_ref,
        ad.year,
        ad.month,
        ad.day,
        MAX(ah.event_type) FILTER(WHERE ah.event_level = 'AGENT') AS agent_status,
        MAX(ah.event_type) FILTER(WHERE ah.capability_type = 'SUPPLY_ACQUISITION') AS cap_supply_aq_status,
        MAX(ah.event_type) FILTER(WHERE ah.capability_type = 'SUPPLY_CONVERSION_CONSULTANCY') AS cap_supply_conv_status,
        MAX(ah.event_type) FILTER(WHERE ah.capability_type = 'DEMAND_VISIT_MANAGEMENT') AS cap_demand_visit_status,
        MAX(ah.event_type) FILTER(WHERE ah.capability_type = 'DEMAND_ACQUISITION') AS cap_demand_aq_status,
        MAX(ah.event_type) FILTER(WHERE ah.capability_type = 'NEGOTIATION') AS cap_negotiation_status,
        MAX(ah.ts_started) FILTER(WHERE ah.event_level = 'AGENT') AS ts_last_status_changed
    FROM
        agent_date AS ad
    LEFT JOIN
        segmentation_activation_history AS ah
            ON ad.id_agent = ah.id_agent
            AND ad.dt_ref = ah.dt_reference
    GROUP BY 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
),
visit_demand_history AS (
    SELECT
        daily_status.id_agent_daily,
        visit_demand_history.business_context = 'SALE' AS is_allow_demand_sale,
        visit_demand_history.business_context = 'RENT' AS is_allow_demand_rent,
        visit_demand_history.passive_lead_receiver AS is_passive_lead_receiver,
        ROW_NUMBER() OVER(PARTITION BY daily_status.id_agent_daily ORDER BY visit_demand_history.updated_at DESC) = 1 AS is_last_update
    FROM
        daily_status
    LEFT JOIN
        datalake_ebdb_transactional.DemandVisitManagementCapabilitySettings AS visit_demand_history
            ON daily_status.id_capability_demand_visit = visit_demand_history.capability_id
            AND daily_status.dt_ref >= DATE(visit_demand_history.updated_at)
),
tier AS (
    SELECT
        daily_status.id_agent_daily,
        MAX(pt.id_tier) FILTER(WHERE pt.incentive_system = 'DEMAND_CONVERSION_FR') AS sk_tier_demand_conversion_fr,
        MAX(pt.id_tier) FILTER(WHERE pt.incentive_system = 'DEMAND_CONVERSION_FS') AS sk_tier_demand_conversion_fs
    FROM
        daily_status
    JOIN
        datalake_big_agent.partner_tier AS pt
            ON daily_status.uuid_person = pt.uuid_person
            AND daily_status.dt_ref >= pt.dt_validity_started
            AND daily_status.dt_ref <= pt.dt_validity_ended
    WHERE
        pt.is_valid
    GROUP BY 1
),
old_agent_history AS (
    SELECT
        daily_status.id_agent_daily,
        ad.is_passive_lead_receiver,
        ROW_NUMBER() OVER(PARTITION BY daily_status.id_agent_daily ORDER BY ure.ts_revision DESC) = 1 AS is_last_update
    FROM
        datalake_ebdb_clean.agent_data_aud AS ad
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ad.rev = ure.id
    JOIN
        daily_status
            ON ad.id = daily_status.id_agent_data
            AND daily_status.dt_ref >= DATE(ure.ts_revision)
)
SELECT
    sk_agent_daily,
    sk_agent,
    sk_agent_data,
    sk_partner,
    sk_user,
    sk_broker,
    sk_tier_demand_conversion_fr,
    sk_tier_demand_conversion_fs,
    uuid_company,
    uuid_agent,
    uuid_person,
    creci,
    creci_uf,
    affiliation_type,
    profile,
    is_agent_active,
    is_allow_supply_acquisition,
    is_allow_supply_conversion,
    is_allow_demand_visit,
    is_allow_demand_acquisition,
    is_allow_negotiation,
    is_allow_demand_sale,
    is_allow_demand_rent,
    is_passive_lead_receiver,
    is_1p_partnership,
    is_3p_partnership,
    days_in_current_status,
    ts_last_status_changed,
    ts_created,
    dt_ref,
    year,
    month,
    day
FROM (
    SELECT
        ds.id_agent_daily AS sk_agent_daily,
        ds.id_agent AS sk_agent,
        COALESCE(ad.id_agent_data, ds.id_agent_data) AS sk_agent_data,
        COALESCE(ad.id_partner, ds.id_partner) AS sk_partner,
        COALESCE(ad.id_user, ds.id_user) AS sk_user,
        COALESCE(cb.sk_broker, -1) AS sk_broker,
        IF(ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED'), t.sk_tier_demand_conversion_fr, NULL) AS sk_tier_demand_conversion_fr,
        IF(ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED'), t.sk_tier_demand_conversion_fs, NULL) AS sk_tier_demand_conversion_fs,
        COALESCE(ad.uuid_company, ds.uuid_company) AS uuid_company,
        COALESCE(ad.uuid_agent, ds.uuid_agent) AS uuid_agent,
        COALESCE(ad.uuid_person, ds.uuid_person) AS uuid_person,
        COALESCE(ad.creci, ds.creci) AS creci,
        COALESCE(ad.creci_uf, ds.creci_uf) AS creci_uf,
        COALESCE(ad.affiliation_type, ds.affiliation_type) AS affiliation_type,
        product.product_name AS profile,
        IF(ds.agent_status IS NULL, NULL, ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED')) AS is_agent_active,
        IF(ds.cap_supply_aq_status IS NULL, NULL, ds.cap_supply_aq_status IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED')) AS is_allow_supply_acquisition,
        IF(ds.cap_supply_conv_status IS NULL, NULL, ds.cap_supply_conv_status IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED')) AS is_allow_supply_conversion,
        IF(ds.cap_demand_visit_status IS NULL, NULL, ds.cap_demand_visit_status IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED')) AS is_allow_demand_visit,
        IF(ds.cap_demand_aq_status IS NULL, NULL, ds.cap_demand_aq_status IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED')) AS is_allow_demand_acquisition,
        IF(ds.cap_negotiation_status IS NULL, NULL, ds.cap_negotiation_status IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED')) AS is_allow_negotiation,
        vdh.is_allow_demand_sale,
        vdh.is_allow_demand_rent,
        COALESCE(oah.is_passive_lead_receiver, vdh.is_passive_lead_receiver) AS is_passive_lead_receiver,
        COALESCE(ad.is_1p_partnership, ds.is_1p_partnership) AS is_1p_partnership,
        COALESCE(ad.is_3p_partnership, ds.is_3p_partnership) AS is_3p_partnership,
        TIMESTAMPDIFF(DAY, DATE(ds.ts_last_status_changed), ds.dt_ref) AS days_in_current_status,
        ds.ts_last_status_changed,
        COALESCE(ad.ts_created, ds.ts_created) AS ts_created,
        ds.dt_ref,
        ds.year,
        ds.month,
        ds.day,
        -- EMR-safe dedupe backstop: guarantees one row per sk_agent_daily so the
        -- incremental MERGE never sees multiple source rows for the same key.
        -- QUALIFY is not supported on EMR Spark, so we use ROW_NUMBER + outer filter.
        ROW_NUMBER() OVER (
            PARTITION BY ds.id_agent_daily
            ORDER BY ds.dt_ref
        ) AS rn_dedup
    FROM
        daily_status AS ds
    LEFT JOIN
        visit_demand_history AS vdh
            ON vdh.id_agent_daily = ds.id_agent_daily
            AND vdh.is_last_update IS TRUE
    LEFT JOIN
        datalake_agent_accreditation.agent_daily AS ad
            ON ad.id_agent_daily = ds.id_agent_daily
    LEFT JOIN
        old_agent_history AS oah
            ON oah.id_agent_daily = ds.id_agent_daily
            AND oah.is_last_update IS TRUE
    LEFT JOIN
        tier AS t
            ON t.id_agent_daily = ds.id_agent_daily
    LEFT JOIN
        core_brokers.brokers AS cb
            ON COALESCE(ad.uuid_company, ds.uuid_company) = cb.uuid_company
            AND COALESCE(ad.is_3p_partnership, ds.is_3p_partnership) = TRUE
    LEFT JOIN
        datalake_ebdb_agent_events.agent_product AS product
            ON ds.id_agent = product.id_agent
            AND product.is_valid_product IS TRUE
            AND product.is_lastest IS TRUE
    WHERE
        ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED')
        OR (ds.agent_status = 'AGENT_INACTIVATED' AND TIMESTAMPDIFF(DAY, DATE(ds.ts_last_status_changed), ds.dt_ref) < 1)
) AS deduped
WHERE
    rn_dedup = 1