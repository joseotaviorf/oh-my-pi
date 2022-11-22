WITH
contracts_signed AS (
    SELECT
        DISTINCT DATE_TRUNC('week', dt_contract_signed) AS week_cs,
        sk_contract,
        dh.sk_house_listing,
        sk_client,
        cluster,
        'contract signed' AS step
    FROM
        datamarts.performance_marketing_metrics_demand dem
    LEFT JOIN
        datalake_marketing_segmentations_prod.lost_listings dh
         ON dh.sk_house_listing  = dem.sk_house_listing
         AND dh.house_type IS NOT NULL
    WHERE
        dt_contract_signed >= '2021-01-01'
),
rent_flows AS (
    SELECT
        DISTINCT DATE_TRUNC('week', dt_event) AS week_event,
        sk_client,
        cluster,
        COUNT(DISTINCT dem.sk_house_listing) AS rent_flows,
        MAX(ts_event) AS last_event,
        MAX(rent_flows) OVER (PARTITION BY sk_client, week_event) AS max_rent_flows,
        MAX(last_event) OVER (PARTITION BY sk_client, week_event) AS max_client_event
    FROM
        datamarts.performance_marketing_metrics_demand dem
    LEFT JOIN
        datalake_marketing_segmentations_prod.lost_listings dh
         ON dh.sk_house_listing  = dem.sk_house_listing
         AND dh.house_type IS NOT NULL
    WHERE
        dt_event >= '2021-01-01'
    GROUP BY 1, 2, 3
),
max_weekly_rent_flows AS (
    SELECT
        week_event,
        sk_client,
        cluster,
        rent_flows,
        last_event,
        max_rent_flows,
        max_client_event
    FROM
        rent_flows rf
    WHERE
        rent_flows = max_rent_flows
         AND cluster IS NOT NULL
),
amount_of_clusters AS (
    SELECT
        sk_client,
        week_event,
        COUNT(DISTINCT cluster) AS clusters
    FROM
        max_weekly_rent_flows
    GROUP BY 1, 2
),
rent_flows_cluster AS (
    SELECT
        max_weekly_rent_flows.week_event,
        max_weekly_rent_flows.sk_client,
        max_weekly_rent_flows.cluster,
        'top_events' AS step
    FROM
        max_weekly_rent_flows
    INNER JOIN
        amount_of_clusters
         ON amount_of_clusters.sk_client = max_weekly_rent_flows.sk_client
         AND amount_of_clusters.week_event = max_weekly_rent_flows.week_event
         AND amount_of_clusters.clusters > 1
    WHERE
        max_weekly_rent_flows.last_event = max_weekly_rent_flows.max_client_event
    UNION ALL
    SELECT
        max_weekly_rent_flows.week_event,
        max_weekly_rent_flows.sk_client,
        max_weekly_rent_flows.cluster,
        'top_last_events' AS step
    FROM
        max_weekly_rent_flows
    INNER JOIN
        amount_of_clusters
         ON amount_of_clusters.sk_client = max_weekly_rent_flows.sk_client
         AND amount_of_clusters.week_event = max_weekly_rent_flows.week_event
         AND amount_of_clusters.clusters <= 1
)
SELECT
    COALESCE(cs.week_cs, rf.week_event) AS week_event,
    COALESCE(cs.sk_client, rf.sk_client) AS sk_client,
    COALESCE(cs.cluster, rf.cluster) AS cluster,
    DATE_TRUNC('week',DATEADD(day,-1,LEAD(COALESCE(cs.week_cs,rf.week_event)) OVER (PARTITION BY COALESCE(cs.sk_client, rf.sk_client) ORDER BY COALESCE(cs.week_cs,rf.week_event)))) AS week_event_end
FROM
    contracts_signed cs
FULL OUTER JOIN
    rent_flows_cluster rf
     ON rf.week_event = cs.week_cs
     AND rf.sk_client = cs.sk_client
