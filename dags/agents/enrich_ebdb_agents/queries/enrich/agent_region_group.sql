WITH agents_region_aud AS (
    SELECT
        id_agent,
        id_region,
        ts_started,
        COALESCE(LEAD(ts_ended) OVER(PARTITION BY id_agent, id_region ORDER BY ts_revision), '2099-12-31 00:00:00') AS ts_ended
    FROM
        datalake_ebdb_agents.agents_region
    WHERE
        rev_type IN (0,2)
),
daily_region AS (
    SELECT
        DATE(TO_TIMESTAMP(DATE('{year}-{month}-{day}'), 'YYYY-MM-DD HH:mm:ss'))  AS ts_slot,
        ara.id_agent,
        ara.id_region,
        aux.region_code,
        aux.region_code_deprecated
    FROM
        agents_region_aud AS ara
    LEFT JOIN
        datalake_gsheets_clean.auxiliary_region AS aux
            ON aux.id = ara.id_region
    WHERE
        ara.ts_started IS NOT NULL
        AND TO_TIMESTAMP(DATE('{year}-{month}-{day}'), 'YYYY-MM-DD HH:mm:ss') BETWEEN ara.ts_started AND ara.ts_ended
        AND TO_TIMESTAMP(DATE('{year}-{month}-{day}'), 'YYYY-MM-DD HH:mm:ss') > TO_TIMESTAMP(DATE('2018-01-31 00:00:00'), 'YYYY-MM-DD HH:mm:ss')  -- limit date, where aud started to be implemented
    ),
    region_records_union AS (
        SELECT
            *
        FROM
            daily_region
        UNION ALL
        SELECT DISTINCT
            ag.ts_slot,
            ag.id_agent,
            ar.id_region,
            ar.region_code,
            ar.region_code_deprecated
        FROM
            datalake_agenda_allocation.agents_slots AS ag
        LEFT JOIN
          daily_region AS ar
            ON ag.id_agent = ar.id_agent
        WHERE
            ar.id_region IS NOT NULL
            AND ag.id_agent IS NOT NULL
            AND	cast(ag.ts_slot AS DATE) = DATE(TO_TIMESTAMP(DATE('{year}-{month}-{day}'), 'YYYY-MM-DD HH:mm:ss'))
            AND DATE(TO_TIMESTAMP(DATE('{year}-{month}-{day}'), 'YYYY-MM-DD HH:mm:ss')) <= DATE('2018-01-31 00:00:00')  -- limit date, where aud started to be implemented
    ),
    region_records_agg AS (
        SELECT
            region_records_union.ts_slot,
            region_records_union.id_agent,
            region_records_union.region_code,
            COUNT(region_records_union.region_code) AS times,
            RANK() OVER (PARTITION BY region_records_union.id_agent ORDER BY COUNT(region_records_union.region_code) DESC, region_records_union.region_code ASC) AS ranking
        FROM
            region_records_union
        GROUP BY
            region_records_union.ts_slot,
            region_records_union.id_agent,
            region_records_union.region_code
    ),
    region_deprecated_records_agg AS (
        SELECT
            region_records_union.ts_slot,
            region_records_union.id_agent,
            region_records_union.region_code_deprecated,
            COUNT(region_records_union.region_code_deprecated) AS times,
            RANK() OVER (PARTITION BY region_records_union.id_agent ORDER BY COUNT(region_records_union.region_code_deprecated) DESC, region_records_union.region_code_deprecated ASC) AS ranking
        FROM
            region_records_union
        GROUP BY
            region_records_union.ts_slot,
            region_records_union.id_agent,
            region_records_union.region_code_deprecated
    ),
    secondary_area as (
        SELECT
            r2.id_agent,
            r2.ts_slot,
            r2.times,
            FIRST(r2.region_code) AS secondary_area
        FROM
            region_records_agg AS r2
        WHERE
            r2.ranking = 2
        GROUP BY
            r2.id_agent,
            r2.ts_slot,
            r2.times
    ),
    secondary_area_deprecated AS (
        SELECT
            ng2.id_agent,
            ng2.ts_slot,
            ng2.times,
            FIRST(ng2.region_code_deprecated) AS secondary_area_deprecated
        FROM
            region_deprecated_records_agg AS ng2
        WHERE
            ng2.ranking = 2
        GROUP BY
            ng2.id_agent,
            ng2.ts_slot,
            ng2.times
    ),
    region_list AS (
        SELECT
            arh.ts_slot,
            arh.id_agent,
            CAST(collect_list(arh.id_region) AS string) AS regions
        FROM
            region_records_union AS arh
        GROUP BY
            arh.ts_slot,
            arh.id_agent
    ),
agent_region_group AS (
    SELECT
        DATE(g.ts_slot) AS dt,
        g.id_agent AS dadosagente_id,
        list.regions,
        g.region_code AS area,
        r2.secondary_area,
        gn.region_code_deprecated as area_deprecated,
        ng2.secondary_area_deprecated,
        ROW_NUMBER() OVER(PARTITION BY g.id_agent, DATE(g.ts_slot) ORDER BY g.region_code) AS row_n -- temporary fix. We need to find why this table is duplicating
    FROM
        region_records_agg AS g
    LEFT JOIN
        region_list AS list
            ON list.ts_slot = g.ts_slot
                AND list.id_agent = g.id_agent
    LEFT JOIN
        region_deprecated_records_agg AS gn
            ON gn.ts_slot = g.ts_slot
            AND gn.id_agent = g.id_agent
            AND gn.ranking = 1
    LEFT JOIN
        secondary_area AS r2
            ON r2.id_agent = g.id_agent
            AND r2.ts_slot = g.ts_slot
            AND r2.times = g.times
    LEFT JOIN
        secondary_area_deprecated AS ng2
            ON ng2.id_agent = g.id_agent
            AND ng2.ts_slot = g.ts_slot
            AND ng2.times = g.times
    WHERE
        g.ranking = 1
)
SELECT
    dt,
    dadosagente_id,
    regions,
    area,
    secondary_area,
    area_deprecated,
    secondary_area_deprecated,
    EXTRACT(YEAR FROM dt) AS year,
    EXTRACT(MONTH FROM dt) AS month,
    EXTRACT(DAY FROM dt) AS day
FROM
    agent_region_group
WHERE
    row_n = 1
