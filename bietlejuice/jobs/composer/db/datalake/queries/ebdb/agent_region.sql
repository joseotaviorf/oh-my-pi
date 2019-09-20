WITH
    agente_region_hist AS (
        SELECT
            DadosAgente_Regiao_AUD.DadosAgente_id AS id_agent_data,
            DadosAgente_Regiao_AUD.regioes_id AS id_region,
            CASE DadosAgente_Regiao_AUD.REVTYPE
                WHEN 0 THEN from_unixtime(floor(UsuarioRevisionEntity.timestamp/1000))
                ELSE NULL END AS ts_start,
            CASE DadosAgente_Regiao_AUD.REVTYPE
                WHEN 2 THEN from_unixtime(floor(UsuarioRevisionEntity.timestamp/1000))
                ELSE NULL END AS ts_end,
            DadosAgente_Regiao_AUD.REVTYPE AS revtype,
            from_unixtime(floor(UsuarioRevisionEntity.timestamp/1000)) AS ts
        FROM
            datalake_ebdb_raw.DadosAgente_Regiao_AUD AS DadosAgente_Regiao_AUD
            LEFT JOIN datalake_ebdb_raw.UsuarioRevisionEntity AS UsuarioRevisionEntity
                ON DadosAgente_Regiao_AUD.rev = UsuarioRevisionEntity.id
    ),
    agent_region_current AS (
        SELECT
            DadosAgente_id AS id_agent_data,
            regioes_id AS id_region,
            NULL AS ts_start,
            timestamp('2099-12-31 00:00:00') AS ts_end,
            3 AS revtype, -- Using 3 to determine that this register is from current data, not an addition (0) or deletion (2)
            timestamp('2099-12-31 00:00:00') AS ts
        FROM
            datalake_ebdb_raw.DadosAgente_Regiao
    ),
    hist_and_current_union AS (
        SELECT
            *
        FROM
            agent_region_current
        UNION ALL
        SELECT
            *
        FROM
            agente_region_hist
    ),
    agent_region_start_order AS (
        SELECT
            agente_region_hist.id_agent_data,
            agente_region_hist.ts,
            row_number() OVER (
                PARTITION BY agente_region_hist.id_agent_data
                ORDER BY agente_region_hist.ts_start DESC
            ) AS ts_start_rank
        FROM
            agente_region_hist
            JOIN hist_and_current_union
                ON agente_region_hist.id_agent_data = hist_and_current_union.id_agent_data
        WHERE
            agente_region_hist.id_region = hist_and_current_union.id_region
            AND agente_region_hist.ts_start < hist_and_current_union.ts_end
            AND agente_region_hist.ts_start IS NOT NULL
    )
SELECT
    hist_and_current_union.id_agent_data,
    hist_and_current_union.id_region,
    coalesce(agent_region_start_order.ts, timestamp('2009-12-31 00:00:00')) AS ts_start,
    timestamp(ts_end) AS ts_end,
    hist_and_current_union.revtype,
    timestamp('2009-12-31 00:00:00') AS ts
FROM
    hist_and_current_union
    LEFT JOIN agent_region_start_order
        ON hist_and_current_union.id_agent_data = agent_region_start_order.id_agent_data
        AND agent_region_start_order.ts_start_rank = 1
WHERE
    ts_end IS NOT NULL
ORDER BY
    ts_end DESC
