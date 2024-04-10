WITH dim_cib AS (
    SELECT
        CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS BIGINT) AS id_user,
        DATE(GET_JSON_OBJECT(a.details, '$.registeredAt')) AS dt_registered
    FROM
        datalake_big_agent.agent AS a
    INNER JOIN
        datalake_ebdb_user.user AS u
            ON u.id = GET_JSON_OBJECT(a.details, '$.userExternalId')
    WHERE
        u.country_code = 'MX'
),
last_rule_global_variables AS (
    SELECT
        MAX(dt_modification) AS dt_last_modification
    FROM
        datalake_gsheets_clean.mexico_cib_segmentation_rules_global_variables
    WHERE
        dt_modification <= MAKE_DATE({year},{month},{day}) + INTERVAL 1 DAY
),
global_variables AS (
    SELECT
        g.shorter_months_calculation,
        g.longer_months_calculation,
        g.dt_modification AS dt_last_modification
    FROM
        datalake_gsheets_clean.mexico_cib_segmentation_rules_global_variables AS g
    INNER JOIN
        last_rule_global_variables AS lr
            ON lr.dt_last_modification = g.dt_modification
),
last_rule_segmentation_variables AS (
    SELECT
        MAX(dt_modification) AS dt_last_modification
    FROM
        datalake_gsheets_clean.mexico_cib_segmentation_rules_segmentation_variables
    WHERE
        dt_modification <= MAKE_DATE({year},{month},{day}) + INTERVAL 1 DAY
),
segmentation_variables AS (
    SELECT
        g.id_segmentation,
        g.name_segmentation,
        g.min_months_registered,
        g.max_months_registered,
        g.min_fl,
        g.max_fl,
        g.min_cs,
        g.max_cs,
        g.dt_modification AS dt_last_modification
    FROM
        datalake_gsheets_clean.mexico_cib_segmentation_rules_segmentation_variables AS g
    INNER JOIN
        last_rule_segmentation_variables AS lr
            ON lr.dt_last_modification = g.dt_modification
),
base_months_since_registration AS (
    SELECT DISTINCT
        dc.id_user,
        dc.dt_registered,
        ROUND(MONTHS_BETWEEN(ad.month_end, dc.dt_registered), 1) AS months_registered,
        (ad.month_end + INTERVAL 1 DAY) AS dt_month_started_segmentation,
        GREATEST(ad.month_start, dc.dt_registered) AS dt_started,
        ad.month_end AS dt_ended,
        gv.shorter_months_calculation,
        gv.longer_months_calculation
    FROM
        datalake_quintoandar.aux_date AS ad
    INNER JOIN
        dim_cib AS dc
            ON ad.month_start >= DATE_TRUNC('month' , dt_registered)
            AND ad.month_start <= MAKE_DATE({year}, {month}, 01)
    INNER JOIN
        global_variables AS gv
            ON (ad.month_end + INTERVAL 1 DAY) >= ADD_MONTHS(gv.dt_last_modification, -(gv.longer_months_calculation-1))
    WHERE
        dc.id_user IS NOT NULL
        AND ad.month_start >= GREATEST(ADD_MONTHS(MAKE_DATE({year}, {month}, 01), -(gv.longer_months_calculation-1)), DATE_TRUNC('month', dt_registered))
),
events_by_month AS (
    SELECT
        bmsr.id_user,
        SUM(IF(ce.event_type = 'FL', 1, 0)) AS first_listings,
        SUM(IF(ce.event_type = 'CS', 1, 0)) AS contracts_signed,
        bmsr.dt_started
    FROM
        base_months_since_registration AS bmsr
    LEFT JOIN
        datalake_mexico_cib_events.cib_events AS ce
            ON ce.id_cib = bmsr.id_user
            AND DATE_TRUNC('month', ce.dt_event) = DATE_TRUNC('month', bmsr.dt_started)
    GROUP BY
        1, 4
),
sum_calculation_shorter_months AS (
    SELECT
        ebm.id_user,
        SUM(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY ebm.id_user) AS sum_fl,
        SUM(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY ebm.id_user) AS sum_cs,
        ebm.dt_started
    FROM
        base_months_since_registration AS bmsr
    INNER JOIN
        events_by_month AS ebm
            ON ebm.id_user = bmsr.id_user
            AND ebm.dt_started = bmsr.dt_started
    WHERE
        bmsr.months_registered <= bmsr.longer_months_calculation
        AND ebm.dt_started >= ADD_MONTHS(MAKE_DATE({year}, {month}, 01), -(bmsr.shorter_months_calculation-1))
),
segmentation_rule_calculation AS (
    SELECT
        bmsr.id_user AS id_cib,
        'SUM' AS type_calculation,
        IF(
            bmsr.months_registered <= bmsr.longer_months_calculation,
            scsm.sum_fl,
            SUM(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY bmsr.id_user)
        ) AS sum_fl,
        IF(
            bmsr.months_registered <= bmsr.longer_months_calculation,
            scsm.sum_cs,
            SUM(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY bmsr.id_user)
        ) AS sum_cs,
        bmsr.months_registered,
        IF(months_registered <= bmsr.longer_months_calculation, bmsr.shorter_months_calculation, bmsr.longer_months_calculation) AS months_calculation,
        bmsr.dt_month_started_segmentation,
        IF(months_registered <= bmsr.longer_months_calculation, GREATEST(ADD_MONTHS(bmsr.dt_started, -((bmsr.shorter_months_calculation)-1)), bmsr.dt_registered), GREATEST(ADD_MONTHS(bmsr.dt_started, -((bmsr.longer_months_calculation)-1)), bmsr.dt_registered)) AS dt_started,
        bmsr.dt_ended,
        YEAR(dt_month_started_segmentation) AS year,
        MONTH(dt_month_started_segmentation) AS month
    FROM
        base_months_since_registration AS bmsr
    INNER JOIN
        events_by_month AS ebm
            ON ebm.id_user = bmsr.id_user
            AND ebm.dt_started = bmsr.dt_started
    LEFT JOIN
        sum_calculation_shorter_months AS scsm
            ON scsm.id_user = bmsr.id_user
            AND scsm.dt_started = bmsr.dt_started
)
SELECT
    id_cib,
    sv.id_segmentation,
    type_calculation,
    sv.name_segmentation AS segmentation,
    DOUBLE(sum_fl) AS first_listings,
    DOUBLE(sum_cs) AS contracts_signed,
    months_registered,
    months_calculation,
    dt_month_started_segmentation,
    dt_started,
    dt_ended,
    year,
    month
FROM
    segmentation_rule_calculation AS src
INNER JOIN
    segmentation_variables AS sv
        ON src.dt_month_started_segmentation >= sv.dt_last_modification
        AND months_registered >= sv.min_months_registered
        AND months_registered <= sv.max_months_registered
        AND sum_fl >= sv.min_fl
        AND sum_fl <= sv.max_fl
        AND sum_cs >= sv.min_cs
        AND sum_cs <= sv.max_cs
WHERE
    dt_month_started_segmentation = MAKE_DATE({year},{month},{day}) + INTERVAL 1 DAY
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_cib, dt_month_started_segmentation ORDER BY sv.id_segmentation DESC) = 1
