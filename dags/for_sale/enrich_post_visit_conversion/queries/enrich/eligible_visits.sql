-- Completed visits eligible for post-visit conversion analysis, snapshotted per run date.
-- No visit is removed: each row is tagged with the first removal rule that applies, or NULL
-- when the visit stays eligible. Filter on removal_rule IS NULL to select eligible visits.
WITH done_visits AS (
    SELECT
        vis.id_visitor,
        vis.id_house,
        vis.id_visit,
        vis.code AS visit_code,
        vis.business_context,
        (DATE(vis.ts_visit_done) >= DATE_SUB(CURRENT_DATE(), 3)) AS is_eligible,
        vis.ts_created,
        vis.ts_visit,
        vis.ts_visit_done
    FROM
        datalake_visit.visits AS vis
    WHERE
        DATE(vis.ts_visit_done) BETWEEN DATE_SUB(CURRENT_DATE(), 14) AND DATE_SUB(CURRENT_DATE(), 1)
        AND vis.computed_status = 'DONE'
        AND vis.id_visitor <> vis.id_agent
        AND vis.id_visitor <> vis.id_owner
),
non_agent_users AS (
    SELECT
        usr.id AS id_user,
        usr.uuid_person
    -- Keep `user` unquoted: the dependency generator matches tables with \w+\.\w+ and
    -- backticks would silently drop ebdb_user_fast_lane from dependencies.yaml.
    FROM
        datalake_ebdb_clean.user AS usr
    WHERE
        usr.id_agent IS NULL
),
visits_already_notified_last_7d AS (
    SELECT DISTINCT
        -- EMR-safe rewrite of Databricks variant access: event_properties is JSON text.
        COALESCE(
            GET_JSON_OBJECT(cms.event_properties, '$.metadata.visit_code'),
            GET_JSON_OBJECT(cms.event_properties, '$.metadata.visitCode')
        ) AS visit_code
    FROM
        datalake_cdp_clean.comms AS cms
    WHERE
        MAKE_DATE(cms.year, cms.month, cms.day) >= DATE_SUB(CURRENT_DATE(), 10)
        AND cms.comms_template IN (
            'visits_fearmissingoutsingle_tnt_wpp_v1',
            'visits_pricingsingle_tnt_wpp_v1'
        )
        AND cms.ts_event >= DATE_SUB(CURRENT_DATE(), 7)
),
users_already_notified_last_7d AS (
    SELECT DISTINCT
        dvi.id_visitor AS id_user
    FROM
        done_visits AS dvi
    INNER JOIN
        visits_already_notified_last_7d AS van
            ON van.visit_code = dvi.visit_code
),
visits_received_finalization_last_24h AS (
    SELECT DISTINCT
        -- EMR-safe rewrite of Databricks variant access: event_properties is JSON text.
        COALESCE(
            GET_JSON_OBJECT(cms.event_properties, '$.metadata.visit_code'),
            GET_JSON_OBJECT(cms.event_properties, '$.metadata.visitCode')
        ) AS visit_code
    FROM
        datalake_cdp_clean.comms AS cms
    WHERE
        MAKE_DATE(cms.year, cms.month, cms.day) >= DATE_SUB(CURRENT_DATE(), 3)
        AND cms.comms_template = 'visits_confirm_finalization_demand_wpp'
        AND cms.ts_event >= (CURRENT_TIMESTAMP() - INTERVAL 1 DAY)
),
users_received_finalization_last_24h AS (
    SELECT DISTINCT
        dvi.id_visitor AS id_user
    FROM
        done_visits AS dvi
    INNER JOIN
        visits_received_finalization_last_24h AS vrf
            ON vrf.visit_code = dvi.visit_code
),
sale_offers AS (
    SELECT
        hse.id_external AS id_house,
        byr.id_external AS id_user,
        MAX(IF(ccv.status = 'SIGNED', TRUE, FALSE)) AS is_contract_signed
    FROM
        datalake_sales_flow_clean.sales_flow AS sfl
    INNER JOIN
        datalake_sales_flow_clean.house AS hse
            ON hse.id = sfl.id_house
    INNER JOIN
        datalake_sales_flow_clean.users AS byr
            ON byr.id = sfl.id_buyer
    LEFT JOIN
        datalake_sales_flow_clean.ccv AS ccv
            ON ccv.id_sales_flow = sfl.id
    WHERE
        MAKE_DATE(sfl.year, sfl.month, sfl.day) >= DATE_SUB(CURRENT_DATE(), 45)
        AND sfl.ts_updated >= DATE_SUB(CURRENT_DATE(), 30)
    GROUP BY
        hse.id_external,
        byr.id_external
),
sale_contracts AS (
    SELECT DISTINCT
        sof.id_user
    FROM
        sale_offers AS sof
    WHERE
        sof.is_contract_signed = TRUE
),
rent_offers AS (
    SELECT DISTINCT
        off.id_house_external AS id_house,
        off.id_tenant_external AS uuid_person
    FROM
        datalake_rental_transact_clean.offer AS off
    WHERE
        off.ts_updated >= DATE_SUB(CURRENT_DATE(), 30)
),
rent_contracts AS (
    SELECT DISTINCT
        id_user
    FROM
        datalake_ebdb_clean.contract AS ctr
    WHERE
        ctr.ts_signed >= DATE_SUB(CURRENT_DATE(), 30)
        AND status = 'Ativo'
),
visit_status_by_demand AS (
    WITH visit_status_by_demand_ranked AS (
        SELECT
            vsl.id_visit,
            CASE
                WHEN vsl.event_type IN ('ANSWER_VISIT_DONE', 'ANSWER_DONE') THEN TRUE
                WHEN vsl.event_type IN ('ANSWER_VISIT_UNSUCCESSFUL', 'ANSWER_UNSUCCESSFUL') THEN FALSE
                ELSE NULL
            END AS is_visit_completed_by_demand,
            vsl.ts_created,
            ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created DESC) AS rn
        FROM
            datalake_ebdb_clean.visit_status_log AS vsl
        WHERE
            vsl.ts_created >= DATE_SUB(CURRENT_DATE(), 30)
            AND vsl.event_type IN ('ANSWER_VISIT_DONE', 'ANSWER_DONE', 'ANSWER_VISIT_UNSUCCESSFUL', 'ANSWER_UNSUCCESSFUL')
            AND vsl.on_behalf_of = 'DEMAND'
    )
    SELECT
        id_visit,
        is_visit_completed_by_demand,
        ts_created
    FROM
        visit_status_by_demand_ranked
    WHERE
        rn = 1
),
visit_house_rating AS (
    WITH visit_house_rating_ranked AS (
        SELECT
            SPLIT_PART(r.id_reviewed, '-', 1) AS visit_code,
            rf.rating_selected[0] AS house_rating,
            r.dt_creation AS ts_created,
            ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) AS rn
        FROM
            datalake_insider_clean.review_feature AS rf
        INNER JOIN
            datalake_insider_clean.review AS r
                ON rf.id_review = r.id
                AND r.type = 'post_visit_house_rating'
                AND r.dt_creation >= DATE_SUB(CURRENT_DATE(), 30)
        INNER JOIN
            datalake_insider_clean.feature AS f
                ON rf.id_feature = f.id
                AND f.id = 111
    )
    SELECT
        visit_code,
        house_rating,
        ts_created
    FROM
        visit_house_rating_ranked
    WHERE
        rn = 1
),
eligible_visits_snapshot AS (
    SELECT
        nau.id_user,
        dvi.id_house,
        dvi.id_visit,
        nau.uuid_person,
        dvi.visit_code,
        dvi.business_context,
        CASE
            WHEN vsd.is_visit_completed_by_demand IS FALSE THEN 'user_contested_the_visit'
            WHEN vhr.house_rating = 'yes'
                AND vhr.ts_created >= (CURRENT_TIMESTAMP() - INTERVAL 2 DAY) THEN 'user_finalized_and_incentivized_recently'
            WHEN vhr.house_rating IN ('partially', 'no') THEN 'user_did_not_like_house'
            WHEN lbc.id_house IS NULL THEN 'house_unpublished'
            WHEN sof.id_house IS NOT NULL THEN 'user_already_sent_house_sale_offer'
            WHEN sco.id_user IS NOT NULL THEN 'user_signed_sale_contract_recently'
            WHEN rof.id_house IS NOT NULL THEN 'user_already_sent_house_rent_offer'
            WHEN rco.id_user IS NOT NULL THEN 'user_signed_rent_contract_recently'
            WHEN urf.id_user IS NOT NULL THEN 'user_received_finalization_recently'
            WHEN uan.id_user IS NOT NULL THEN 'user_received_offer_incentive_recently'
            ELSE NULL
        END AS removal_rule,
        dvi.ts_created,
        dvi.ts_visit,
        dvi.ts_visit_done,
        CURRENT_TIMESTAMP() AS ts_snapshot,
        YEAR(CURRENT_DATE()) AS year,
        MONTH(CURRENT_DATE()) AS month,
        DAY(CURRENT_DATE()) AS day,
        -- Guard against residual fan-out from upstream joins (e.g. duplicate published
        -- listing_business_context rows); keep one row per visit per snapshot.
        ROW_NUMBER() OVER(PARTITION BY dvi.id_visit ORDER BY dvi.ts_created DESC) AS rn
    FROM
        done_visits AS dvi
    INNER JOIN
        non_agent_users AS nau
            ON dvi.id_visitor = nau.id_user
    LEFT JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = dvi.id_house
            AND LOWER(lbc.business_context) = LOWER(dvi.business_context)
            AND LOWER(lbc.status) = 'published'
    LEFT JOIN
        visit_status_by_demand AS vsd
            ON vsd.id_visit = dvi.id_visit
    LEFT JOIN
        visit_house_rating AS vhr
            ON vhr.visit_code = dvi.visit_code
    LEFT JOIN
        users_already_notified_last_7d AS uan
            ON uan.id_user = dvi.id_visitor
    LEFT JOIN
        users_received_finalization_last_24h AS urf
            ON urf.id_user = dvi.id_visitor
    LEFT JOIN
        sale_offers AS sof
            ON sof.id_user = dvi.id_visitor
            AND sof.id_house = dvi.id_house
            AND dvi.business_context = 'SALE'
    LEFT JOIN
        sale_contracts AS sco
            ON sco.id_user = dvi.id_visitor
            AND dvi.business_context = 'SALE'
    LEFT JOIN
        rent_offers AS rof
            ON rof.uuid_person = nau.uuid_person
            AND rof.id_house = dvi.id_house
            AND dvi.business_context = 'RENT'
    LEFT JOIN
        rent_contracts AS rco
            ON rco.id_user = dvi.id_visitor
            AND dvi.business_context = 'RENT'
    WHERE
        dvi.is_eligible = TRUE
)
SELECT
    CONCAT_WS('_', CAST(id_visit AS STRING), CAST(year AS STRING), CAST(month AS STRING), CAST(day AS STRING)) AS id,
    id_user,
    id_house,
    id_visit,
    uuid_person,
    visit_code,
    business_context,
    removal_rule,
    ts_created,
    ts_visit,
    ts_visit_done,
    ts_snapshot,
    year,
    month,
    day
FROM
    eligible_visits_snapshot
WHERE
    rn = 1
