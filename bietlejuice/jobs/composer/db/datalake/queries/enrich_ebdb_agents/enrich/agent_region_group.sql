WITH 
    agent_region_date_filter AS (
        SELECT  
            *
        FROM 
            datalake_ebdb_user_revision_entity.user_revision_entity b
        WHERE 
            b.ts_revision >= date_add(current_date, -1)
    ),
    agent_region_daily AS (

        SELECT 
            a.id_agent_data AS id_agent,
            a.id_region,
            MAX(CASE WHEN a.rev_type = 0 THEN b.ts_revision ELSE null END) AS dt_start,
            COALESCE(MAX(CASE WHEN a.rev_type = 2 THEN b.ts_revision ELSE null END), '2099-12-31 00:00:00') AS dt_end,
            MIN(a.rev_type) AS rev_type
        FROM 
            datalake_ebdb_clean.agent_region_data_aud a
        JOIN 
            agent_region_date_filter b
                ON a.rev = b.id
        WHERE 
            a.rev_type IN (0, 2)
        GROUP BY 
            1, 2
        HAVING 
            MIN(a.rev_type) = 0
    ),
    daily_region AS (
        SELECT 
            DATE(TO_TIMESTAMP(current_date, 'YYYY-MM-DD HH:mm:ss'))  AS ts_slot,
            t_out.id_agent,
            t_out.id_region,
            aux.region_code,
            aux.region_code_deprecated
        FROM
            agent_region_daily t_out
        LEFT join
            datalake_gsheets_clean.auxiliary_region aux ON aux.id = t_out.id_region
        WHERE
            TO_TIMESTAMP(current_date, 'YYYY-MM-DD HH:mm:ss') > TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH:mm:ss')  -- limit date, where aud started to be implemented
        ORDER BY 2, 4
    ),
    region_records_union AS (
        SELECT
            *
        FROM 
            daily_region
        UNION ALL
        SELECT DISTINCT
            ag.ts_slot,
            us.dados_agente_id AS id_agent,
            ar.id_region,
            aux.region_code,
            aux.region_code_deprecated
        FROM
            datalake_ebdb_agents.agents_slots ag
        LEFT JOIN datalake_ebdb_agents.agents_region ar
            ON ag.id_agent = ar.id_agent
        LEFT JOIN dw_public.dim_user us
            ON us.dados_agente_id = ag.id_agent
        LEFT JOIN datalake_gsheets_clean.auxiliary_region aux
            ON aux.id = ar.id_region
        WHERE
            ar.id_region IS NOT NULL
            AND us.dados_agente_id IS NOT NULL
            AND ag.is_available_slot = TRUE
            AND DATE(TO_TIMESTAMP(current_date, 'YYYY-MM-DD HH:mm:ss')) >= DATE('2018-01-31 00:00:00')  -- limit date, where aud started to be implemented
    ),
    region_records_agg AS (
        SELECT
            region_records_union.ts_slot,
            region_records_union.id_agent,
            region_records_union.region_code,
            count(region_records_union.region_code) AS times,
            RANK() OVER (PARTITION BY region_records_union.id_agent ORDER BY count(region_records_union.region_code) DESC, region_records_union.region_code ASC) ranking
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
            count(region_records_union.region_code_deprecated) AS times,
            RANK() OVER (PARTITION BY region_records_union.id_agent ORDER BY count(region_records_union.region_code_deprecated) DESC, region_records_union.region_code_deprecated ASC) ranking
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
            first(r2.region_code) AS secondary_area
        FROM 
            region_records_agg r2
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
            first(ng2.region_code_deprecated) AS secondary_area_deprecated
        FROM 
            region_deprecated_records_agg ng2
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
            region_records_union arh
        GROUP BY
            arh.ts_slot,
            arh.id_agent
    )
SELECT
	g.ts_slot AS dt,
	g.id_agent AS dadosagente_id,
	list.regions,
	g.region_code AS area,
	r2.secondary_area,
    gn.region_code_deprecated as area_deprecated,
    ng2.secondary_area_deprecated
FROM 
    region_records_agg g
LEFT JOIN
	region_list list
        ON list.ts_slot = g.ts_slot 
            AND list.id_agent = g.id_agent
LEFT JOIN
    region_deprecated_records_agg gn
        ON gn.ts_slot = g.ts_slot 
            AND gn.id_agent = g.id_agent 
            AND gn.ranking = 1
LEFT JOIN
    secondary_area r2
        ON r2.id_agent = g.id_agent
            AND r2.ts_slot = g.ts_slot
            AND r2.times = g.times
LEFT JOIN
    secondary_area_deprecated ng2
        ON ng2.id_agent = g.id_agent
            AND ng2.ts_slot = g.ts_slot
            AND ng2.times = g.times
WHERE 
    g.ranking = 1