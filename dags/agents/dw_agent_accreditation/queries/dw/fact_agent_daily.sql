WITH agent_date AS (
    SELECT
        MD5(CONCAT(agent.id_agent, aux_date.date)) AS id_agent_daily,
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
        aux_date.date AS dt_ref,
        YEAR(aux_date.date) AS year,
        MONTH(aux_date.date) AS month,
        DAY(aux_date.date) AS day
    FROM
        datalake_agent_accreditation.agent
    JOIN
        datalake_quintoandar.aux_date
            ON aux_date.date >= DATE(agent.ts_created)
            AND aux_date.date <= CURRENT_DATE
    WHERE
        aux_date.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
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
        activation_history AS ah
            ON ad.id_agent = ah.id_agent
            AND ad.dt_ref >= ah.dt_started
            AND ad.dt_ref < COALESCE(ah.dt_ended, CURRENT_DATE+1)
    GROUP BY ALL
),
visit_demand_history AS (
    WITH visit_demand_history_ranked AS (
        SELECT
            daily_status.id_agent_daily,
            visit_demand_history.business_context = 'SALE' AS is_allow_demand_sale,
            visit_demand_history.business_context = 'RENT' AS is_allow_demand_rent,
            visit_demand_history.passive_lead_receiver AS is_passive_lead_receiver,
            ROW_NUMBER() OVER(PARTITION BY daily_status.id_agent_daily ORDER BY visit_demand_history.updated_at DESC) AS rn
        FROM
            daily_status
        LEFT JOIN
            datalake_ebdb_transactional.DemandVisitManagementCapabilitySettings AS visit_demand_history
                ON daily_status.id_capability_demand_visit = visit_demand_history.capability_id
                AND daily_status.dt_ref >= DATE(visit_demand_history.updated_at)
    )
    SELECT
        id_agent_daily,
        is_allow_demand_sale,
        is_allow_demand_rent,
        is_passive_lead_receiver
    FROM
        visit_demand_history_ranked
    WHERE
        rn = 1
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
    WITH old_agent_history_ranked AS (
        SELECT
            daily_status.id_agent_daily,
            ad.is_passive_lead_receiver,
            ROW_NUMBER() OVER(PARTITION BY daily_status.id_agent_daily ORDER BY ure.ts_revision DESC) AS rn
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
        id_agent_daily,
        is_passive_lead_receiver
    FROM
        old_agent_history_ranked
    WHERE
        rn = 1
)
SELECT
    ds.id_agent_daily AS sk_agent_daily,
    ds.id_agent AS sk_agent,
    COALESCE(ad.id_agent_data, ds.id_agent_data) AS sk_agent_data,
    COALESCE(ad.id_partner, ds.id_partner) AS sk_partner,
    COALESCE(ad.id_user, ds.id_user) AS sk_user,
    IF(ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED'), t.sk_tier_demand_conversion_fr, NULL) AS sk_tier_demand_conversion_fr,
    IF(ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED'), t.sk_tier_demand_conversion_fs, NULL) AS sk_tier_demand_conversion_fs,
    COALESCE(ad.uuid_company, ds.uuid_company) AS uuid_company,
    COALESCE(ad.uuid_agent, ds.uuid_agent) AS uuid_agent,
    COALESCE(ad.uuid_person, ds.uuid_person) AS uuid_person,
    COALESCE(ad.creci, ds.creci) AS creci,
    COALESCE(ad.creci_uf, ds.creci_uf) AS creci_uf,
    COALESCE(ad.affiliation_type, ds.affiliation_type) AS affiliation_type,
    COALESCE(ad.profile, ds.profile) AS profile,
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
    ds.day
FROM
    daily_status AS ds
LEFT JOIN
    visit_demand_history AS vdh
        ON vdh.id_agent_daily = ds.id_agent_daily
LEFT JOIN
    datalake_agent_accreditation.agent_daily AS ad
        ON ad.id_agent_daily = ds.id_agent_daily
LEFT JOIN
    old_agent_history AS oah
        ON oah.id_agent_daily = ds.id_agent_daily
LEFT JOIN
    tier AS t
        ON t.id_agent_daily = ds.id_agent_daily
WHERE
    ds.agent_status IN ('AGENT_ACTIVATED', 'AGENT_REACTIVATED')
    OR (ds.agent_status = 'AGENT_INACTIVATED' AND TIMESTAMPDIFF(DAY, DATE(ds.ts_last_status_changed), ds.dt_ref) < 1)
