-- Roll-Up ticket model. Reproduces model_tickets in dw_modeling.py, which unions
-- the Superlogica service tickets with the maintenance orders under one shape.
-- Titles carry the Roll-Up convention "name :: person type :: contract code", so the
-- three parts are parsed back out and the contract code is resolved to a contract id.
-- count_checklist_cs numbers the repeats of the same title on the same contract in
-- chronological order. The pandas version breaks ties by extraction order, which the
-- lake does not keep, so ties fall back to the raw mirror id ascending.
-- nr_ordem records the build order the pandas concat produces, so the checklist model
-- can reproduce its last one wins ticket lookup without guessing.
-- Modelled table, not a vendor mirror, hence the benvi_rollup_ prefix. It stays in
-- this DAG and layer because it is pure derivation over the clean projections.
WITH contract_lookup AS (
    SELECT
        ranked.id,
        ranked.id_contrato_con,
        ranked.codigo_contrato
    FROM (
        SELECT
            contrato.id,
            TRIM(contrato.id_contrato_con) AS id_contrato_con,
            TRIM(contrato.codigo_contrato) AS codigo_contrato,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(contrato.codigo_contrato)
                ORDER BY contrato.id
            ) AS rn
        FROM
            datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        WHERE
            TRIM(COALESCE(contrato.id_contrato_con, '')) <> ''
            AND TRIM(COALESCE(contrato.codigo_contrato, '')) <> ''
    ) AS ranked
    WHERE
        ranked.rn = 1
),
contract_by_id AS (
    SELECT
        ranked.id_contrato_con,
        ranked.codigo_contrato
    FROM (
        SELECT
            contract_lookup.id_contrato_con,
            contract_lookup.codigo_contrato,
            ROW_NUMBER() OVER (
                PARTITION BY contract_lookup.id_contrato_con
                ORDER BY contract_lookup.id
            ) AS rn
        FROM
            contract_lookup AS contract_lookup
    ) AS ranked
    WHERE
        ranked.rn = 1
),
ticket_parsed AS (
    SELECT
        ticket.id,
        TRIM(COALESCE(ticket.id_ticket_tic, '')) AS id_ticket_tic,
        COALESCE(ticket.nome_grpu, '') AS st_nome_grpu,
        COALESCE(ticket.titulo_tic, '') AS st_titulo_tic,
        COALESCE(ticket.st_nome_usu, '') AS st_nome_usu,
        CAST(ticket.fl_status_tic AS STRING) AS fl_status_tic,
        ticket.ts_inicioticket_tic,
        ticket.ts_encerrado_tic,
        COALESCE(ticket.id_cliente_tic, '') AS id_cliente_tic,
        CAST(ticket.fl_interno_tic AS STRING) AS fl_interno_tic,
        TRIM(REGEXP_REPLACE(TRIM(COALESCE(ticket.titulo_tic, '')), '(?i)^checklist\\s*-\\s*', ''))
            AS title_norm
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_ticket AS ticket
),
ticket_split AS (
    SELECT
        ticket_parsed.*,
        TRIM(COALESCE(SPLIT(ticket_parsed.title_norm, ' :: ')[0], '')) AS name_checklist,
        TRIM(COALESCE(SPLIT(ticket_parsed.title_norm, ' :: ')[1], '')) AS person_type,
        TRIM(COALESCE(SPLIT(ticket_parsed.title_norm, ' :: ')[2], '')) AS codigo_contrato
    FROM
        ticket_parsed AS ticket_parsed
),
ticket_lookup_name AS (
    SELECT
        ticket_split.*,
        CASE
            WHEN ticket_split.title_norm RLIKE '^(.*) :: [^:]+$'
                THEN TRIM(REGEXP_EXTRACT(ticket_split.title_norm, '^(.*) :: [^:]+$', 1))
            WHEN ticket_split.name_checklist <> '' AND ticket_split.person_type <> ''
                THEN CONCAT(ticket_split.name_checklist, ' :: ', ticket_split.person_type)
            ELSE ticket_split.title_norm
        END AS checklist_lookup_name
    FROM
        ticket_split AS ticket_split
),
checklist_match AS (
    SELECT
        ranked.checklist_lookup_name,
        ranked.id_checklist_chk
    FROM (
        SELECT
            ticket_lookup_name.checklist_lookup_name,
            catalog.id_checklist_chk,
            ROW_NUMBER() OVER (
                PARTITION BY ticket_lookup_name.checklist_lookup_name
                ORDER BY
                    CASE
                        WHEN catalog.st_nome_chk = ticket_lookup_name.checklist_lookup_name THEN 0
                        ELSE 1
                    END,
                    catalog.st_nome_chk,
                    catalog.id_checklist_chk
            ) AS rn
        FROM (
            SELECT DISTINCT
                ticket_lookup_name.checklist_lookup_name
            FROM
                ticket_lookup_name AS ticket_lookup_name
            WHERE
                ticket_lookup_name.checklist_lookup_name <> ''
        ) AS ticket_lookup_name
        INNER JOIN
            datalake_benvi_manager_clean.benvi_rollup_checklist_catalog AS catalog
                ON TRIM(catalog.st_nome_chk) = TRIM(ticket_lookup_name.checklist_lookup_name)
    ) AS ranked
    WHERE
        ranked.rn = 1
),
ticket_row AS (
    SELECT
        'ticket' AS tipo,
        CASE
            WHEN ticket_lookup_name.id_ticket_tic <> ''
                THEN CONCAT('ticket-', ticket_lookup_name.id_ticket_tic)
            ELSE ''
        END AS id_chave,
        ticket_lookup_name.id_ticket_tic AS id_origem,
        ticket_lookup_name.id_ticket_tic,
        ticket_lookup_name.st_nome_grpu,
        ticket_lookup_name.st_titulo_tic,
        ticket_lookup_name.st_nome_usu,
        ticket_lookup_name.fl_status_tic,
        ticket_lookup_name.ts_inicioticket_tic AS dt_inicioticket_tic,
        ticket_lookup_name.ts_encerrado_tic AS dt_encerrado_tic,
        ticket_lookup_name.id_cliente_tic,
        ticket_lookup_name.fl_interno_tic,
        ticket_lookup_name.name_checklist,
        ticket_lookup_name.person_type,
        ticket_lookup_name.codigo_contrato,
        COALESCE(contract_lookup.id_contrato_con, '') AS id_contrato_con,
        COALESCE(checklist_match.id_checklist_chk, '') AS id_checklist_chk,
        CAST(
            ROW_NUMBER() OVER (
                PARTITION BY ticket_lookup_name.st_titulo_tic, ticket_lookup_name.codigo_contrato
                ORDER BY ticket_lookup_name.ts_inicioticket_tic ASC NULLS LAST, ticket_lookup_name.id
            ) AS INT
        ) AS count_checklist_cs,
        CAST(NULL AS STRING) AS st_categoria,
        CAST(NULL AS STRING) AS st_descricao_man,
        CAST(NULL AS STRING) AS st_identificador_man,
        CAST(NULL AS STRING) AS fl_prioridade_man,
        CAST(NULL AS DATE) AS dt_previsaoentrega_man,
        CASE
            WHEN ticket_lookup_name.checklist_lookup_name <> ''
                THEN ticket_lookup_name.checklist_lookup_name
            ELSE ticket_lookup_name.name_checklist
        END AS checklist_lookup_name,
        CAST(
            ROW_NUMBER() OVER (ORDER BY ticket_lookup_name.id) AS BIGINT
        ) AS nr_ordem_branch,
        0 AS nr_branch
    FROM
        ticket_lookup_name AS ticket_lookup_name
    LEFT JOIN
        contract_lookup AS contract_lookup
            ON ticket_lookup_name.codigo_contrato = contract_lookup.codigo_contrato
    LEFT JOIN
        checklist_match AS checklist_match
            ON ticket_lookup_name.checklist_lookup_name = checklist_match.checklist_lookup_name
),
maintenance_parsed AS (
    SELECT
        manutencao.id,
        TRIM(COALESCE(manutencao.id_manutencao_man, '')) AS id_manutencao_man,
        TRIM(COALESCE(manutencao.id_contrato_con, '')) AS id_contrato_con,
        COALESCE(manutencao.st_categoria, '') AS st_categoria,
        COALESCE(manutencao.st_descricao_man, '') AS st_descricao_man,
        COALESCE(manutencao.st_identificador_man, '') AS st_identificador_man,
        CAST(manutencao.fl_prioridade_man AS STRING) AS fl_prioridade_man,
        manutencao.dt_previsaoentrega_man,
        CAST(manutencao.fl_situacao_man AS STRING) AS fl_situacao_man,
        CAST(manutencao.fl_solicitante_man AS STRING) AS fl_solicitante_man,
        manutencao.dt_criacao_man,
        manutencao.dt_atualizacao_man,
        TRIM(REGEXP_REPLACE(
            TRIM(COALESCE(manutencao.st_descricao_man, '')), '(?i)^checklist\\s*-\\s*', ''
        )) AS descricao_norm
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_manutencao AS manutencao
),
maintenance_split AS (
    SELECT
        maintenance_parsed.*,
        TRIM(COALESCE(SPLIT(maintenance_parsed.descricao_norm, ' :: ')[0], '')) AS desc_part_1,
        TRIM(COALESCE(SPLIT(maintenance_parsed.descricao_norm, ' :: ')[1], '')) AS desc_part_2,
        TRIM(COALESCE(SPLIT(maintenance_parsed.descricao_norm, ' :: ')[2], '')) AS desc_part_3
    FROM
        maintenance_parsed AS maintenance_parsed
),
maintenance_title AS (
    SELECT
        maintenance_split.*,
        COALESCE(contract_by_id.codigo_contrato, '') AS codigo_from_contract,
        CASE
            WHEN maintenance_split.desc_part_1 <> '' THEN maintenance_split.desc_part_1
            WHEN maintenance_split.st_categoria <> ''
                THEN CONCAT('[MAN] ', maintenance_split.st_categoria)
            ELSE '[MAN] Manutencao'
        END AS name_fallback,
        CASE maintenance_split.fl_solicitante_man
            WHEN '1' THEN 'IQ'
            WHEN '2' THEN 'PP'
            ELSE 'INT'
        END AS person_fallback
    FROM
        maintenance_split AS maintenance_split
    LEFT JOIN
        contract_by_id AS contract_by_id
            ON maintenance_split.id_contrato_con = contract_by_id.id_contrato_con
),
maintenance_row AS (
    SELECT
        'manutencao' AS tipo,
        CASE
            WHEN titled.id_manutencao_man <> ''
                THEN CONCAT('manutencao-', titled.id_manutencao_man)
            ELSE ''
        END AS id_chave,
        titled.id_manutencao_man AS id_origem,
        '' AS id_ticket_tic,
        '' AS st_nome_grpu,
        titled.st_titulo_tic,
        '' AS st_nome_usu,
        titled.fl_situacao_man AS fl_status_tic,
        titled.dt_criacao_man AS dt_inicioticket_tic,
        titled.dt_atualizacao_man AS dt_encerrado_tic,
        '' AS id_cliente_tic,
        '' AS fl_interno_tic,
        TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[0], '')) AS name_checklist,
        TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[1], '')) AS person_type,
        CASE
            WHEN titled.codigo_from_contract <> '' THEN titled.codigo_from_contract
            ELSE TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[2], ''))
        END AS codigo_contrato,
        titled.id_contrato_con,
        '' AS id_checklist_chk,
        CAST(
            ROW_NUMBER() OVER (
                PARTITION BY
                    titled.st_titulo_tic,
                    CASE
                        WHEN titled.codigo_from_contract <> '' THEN titled.codigo_from_contract
                        ELSE TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[2], ''))
                    END
                ORDER BY titled.dt_criacao_man ASC NULLS LAST, titled.id
            ) AS INT
        ) AS count_checklist_cs,
        titled.st_categoria,
        titled.st_descricao_man,
        titled.st_identificador_man,
        titled.fl_prioridade_man,
        titled.dt_previsaoentrega_man,
        CASE
            WHEN titled.st_titulo_tic RLIKE '^(.*) :: [^:]+$'
                THEN TRIM(REGEXP_EXTRACT(titled.st_titulo_tic, '^(.*) :: [^:]+$', 1))
            WHEN TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[0], '')) <> ''
                AND TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[1], '')) <> ''
                THEN CONCAT_WS(
                    ' :: ',
                    TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[0], '')),
                    TRIM(COALESCE(SPLIT(titled.st_titulo_tic, ' :: ')[1], ''))
                )
            ELSE titled.st_titulo_tic
        END AS checklist_lookup_name,
        CAST(ROW_NUMBER() OVER (ORDER BY titled.id) AS BIGINT) AS nr_ordem_branch,
        1 AS nr_branch
    FROM (
        SELECT
            maintenance_title.*,
            CASE
                WHEN maintenance_title.desc_part_1 <> ''
                    AND maintenance_title.desc_part_2 <> ''
                    AND maintenance_title.desc_part_3 <> ''
                    THEN CONCAT_WS(
                        ' :: ',
                        maintenance_title.desc_part_1,
                        maintenance_title.desc_part_2,
                        maintenance_title.desc_part_3
                    )
                ELSE CONCAT_WS(
                    ' :: ',
                    maintenance_title.name_fallback,
                    maintenance_title.person_fallback,
                    CASE
                        WHEN maintenance_title.codigo_from_contract <> ''
                            THEN maintenance_title.codigo_from_contract
                        ELSE maintenance_title.id_contrato_con
                    END
                )
            END AS st_titulo_tic
        FROM
            maintenance_title AS maintenance_title
    ) AS titled
),
rollup_union AS (
    SELECT * FROM ticket_row
    UNION ALL
    SELECT * FROM maintenance_row
)
SELECT
    rollup_union.tipo,
    rollup_union.id_chave,
    rollup_union.id_origem,
    rollup_union.id_ticket_tic,
    rollup_union.st_nome_grpu,
    rollup_union.st_titulo_tic,
    rollup_union.st_nome_usu,
    rollup_union.fl_status_tic,
    rollup_union.dt_inicioticket_tic,
    rollup_union.dt_encerrado_tic,
    rollup_union.id_cliente_tic,
    rollup_union.fl_interno_tic,
    rollup_union.name_checklist,
    rollup_union.person_type,
    rollup_union.codigo_contrato,
    rollup_union.id_contrato_con,
    rollup_union.id_checklist_chk,
    rollup_union.count_checklist_cs,
    CASE
        WHEN rollup_union.nr_branch = 0
            AND rollup_union.id_checklist_chk <> ''
            AND rollup_union.id_contrato_con <> ''
            THEN CONCAT_WS(
                '-',
                CAST(rollup_union.count_checklist_cs AS STRING),
                rollup_union.id_checklist_chk,
                rollup_union.id_contrato_con
            )
        WHEN rollup_union.nr_branch = 1 AND rollup_union.id_origem <> ''
            THEN CONCAT_WS(
                '-',
                CAST(rollup_union.count_checklist_cs AS STRING),
                'MAN',
                rollup_union.id_origem
            )
        ELSE ''
    END AS id_checklist_cs,
    rollup_union.st_categoria,
    rollup_union.st_descricao_man,
    rollup_union.st_identificador_man,
    rollup_union.fl_prioridade_man,
    rollup_union.dt_previsaoentrega_man,
    rollup_union.checklist_lookup_name,
    CAST(rollup_union.nr_branch AS BIGINT) * 1000000 + rollup_union.nr_ordem_branch AS nr_ordem
FROM
    rollup_union AS rollup_union
