-- Roll-Up checklist model. Reproduces model_checklists in dw_modeling.py, which unions
-- the contract checklist lines with the maintenance order notes under one shape and
-- attaches the ticket that covers each line.
-- Ticket resolution follows the same fallback ladder: by id_checklist_cs, then by
-- checklist and contract, then by checklist name and contract. The pandas version keeps
-- the last ticket per key, so nr_ordem on benvi_rollup_ticket decides the winner here.
-- On the contract side every line of one checklist instance shares dt_checklist_created,
-- so the distinct instance count is always 1 and id_checklist_cs starts at 1.
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
checklist_line AS (
    SELECT
        checklist_item.id,
        TRIM(COALESCE(checklist_item.id_checklist_chk, '')) AS id_checklist_chk,
        TRIM(COALESCE(checklist_item.id_contrato_con, '')) AS id_contrato_con,
        COALESCE(checklist_item.st_nome_cch, '') AS sub_item,
        CAST(checklist_item.fl_status_cch AS STRING) AS sub_item_done,
        CASE
            WHEN checklist_item.fl_status_cch = 1
                THEN COALESCE(
                    checklist_item.ts_ultimanotificacao_cch,
                    checklist_item.ts_envioapp_cch,
                    checklist_item.ts_entregalimite_cch
                )
        END AS ts_sub_item_done,
        TRIM(REGEXP_REPLACE(
            TRIM(COALESCE(checklist_item.st_nome_chk, '')), '(?i)^checklist\\s*-\\s*', ''
        )) AS nome_chk_norm
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_checklist_contrato AS checklist_item
),
checklist_instance AS (
    SELECT
        checklist_line.id,
        checklist_line.id_checklist_chk,
        checklist_line.id_contrato_con,
        checklist_line.sub_item,
        checklist_line.sub_item_done,
        checklist_line.ts_sub_item_done,
        checklist_line.nome_chk_norm,
        TRIM(COALESCE(SPLIT(checklist_line.nome_chk_norm, ' :: ')[0], '')) AS name_checklist,
        TRIM(COALESCE(SPLIT(checklist_line.nome_chk_norm, ' :: ')[1], '')) AS person_type,
        TO_DATE(
            MIN(checklist_line.ts_sub_item_done) OVER (
                PARTITION BY checklist_line.id_checklist_chk, checklist_line.id_contrato_con
            )
        ) AS dt_checklist_created
    FROM
        checklist_line AS checklist_line
),
checklist_keyed AS (
    SELECT
        checklist_instance.id,
        checklist_instance.id_checklist_chk,
        checklist_instance.id_contrato_con,
        checklist_instance.sub_item,
        checklist_instance.sub_item_done,
        checklist_instance.ts_sub_item_done,
        checklist_instance.nome_chk_norm,
        checklist_instance.name_checklist,
        checklist_instance.person_type,
        checklist_instance.dt_checklist_created,
        CASE
            WHEN checklist_instance.id_checklist_chk <> ''
                AND checklist_instance.id_contrato_con <> ''
                THEN CONCAT_WS(
                    '-',
                    '1',
                    checklist_instance.id_checklist_chk,
                    checklist_instance.id_contrato_con
                )
            ELSE ''
        END AS id_checklist_cs
    FROM
        checklist_instance AS checklist_instance
),
ticket_by_cs AS (
    SELECT
        ranked.id_checklist_cs,
        ranked.nr_ordem
    FROM (
        SELECT
            rollup_ticket.id_checklist_cs,
            rollup_ticket.nr_ordem,
            ROW_NUMBER() OVER (
                PARTITION BY rollup_ticket.id_checklist_cs
                ORDER BY rollup_ticket.nr_ordem DESC
            ) AS rn
        FROM
            datalake_benvi_manager_clean.benvi_rollup_ticket AS rollup_ticket
        WHERE
            COALESCE(rollup_ticket.id_checklist_cs, '') <> ''
    ) AS ranked
    WHERE
        ranked.rn = 1
),
ticket_by_chk_contract AS (
    SELECT
        ranked.id_checklist_chk,
        ranked.id_contrato_con,
        ranked.nr_ordem
    FROM (
        SELECT
            rollup_ticket.id_checklist_chk,
            rollup_ticket.id_contrato_con,
            rollup_ticket.nr_ordem,
            ROW_NUMBER() OVER (
                PARTITION BY rollup_ticket.id_checklist_chk, rollup_ticket.id_contrato_con
                ORDER BY rollup_ticket.nr_ordem DESC
            ) AS rn
        FROM
            datalake_benvi_manager_clean.benvi_rollup_ticket AS rollup_ticket
        WHERE
            COALESCE(rollup_ticket.id_checklist_chk, '') <> ''
            AND COALESCE(rollup_ticket.id_contrato_con, '') <> ''
    ) AS ranked
    WHERE
        ranked.rn = 1
),
ticket_by_name_contract AS (
    SELECT
        ranked.checklist_lookup_name,
        ranked.id_contrato_con,
        ranked.nr_ordem
    FROM (
        SELECT
            rollup_ticket.checklist_lookup_name,
            rollup_ticket.id_contrato_con,
            rollup_ticket.nr_ordem,
            ROW_NUMBER() OVER (
                PARTITION BY rollup_ticket.checklist_lookup_name, rollup_ticket.id_contrato_con
                ORDER BY rollup_ticket.nr_ordem DESC
            ) AS rn
        FROM
            datalake_benvi_manager_clean.benvi_rollup_ticket AS rollup_ticket
        WHERE
            COALESCE(rollup_ticket.checklist_lookup_name, '') <> ''
            AND COALESCE(rollup_ticket.id_contrato_con, '') <> ''
    ) AS ranked
    WHERE
        ranked.rn = 1
),
checklist_resolved AS (
    SELECT
        checklist_keyed.id,
        checklist_keyed.id_checklist_cs,
        checklist_keyed.id_contrato_con,
        COALESCE(contract_by_id.codigo_contrato, '') AS codigo_contrato,
        checklist_keyed.name_checklist,
        checklist_keyed.person_type,
        checklist_keyed.sub_item,
        checklist_keyed.sub_item_done,
        checklist_keyed.ts_sub_item_done,
        checklist_keyed.dt_checklist_created,
        COALESCE(
            ticket_by_cs.nr_ordem,
            ticket_by_chk_contract.nr_ordem,
            ticket_by_name_contract.nr_ordem
        ) AS nr_ordem_tkt
    FROM
        checklist_keyed AS checklist_keyed
    LEFT JOIN
        contract_by_id AS contract_by_id
            ON checklist_keyed.id_contrato_con = contract_by_id.id_contrato_con
    LEFT JOIN
        ticket_by_cs AS ticket_by_cs
            ON checklist_keyed.id_checklist_cs = ticket_by_cs.id_checklist_cs
    LEFT JOIN
        ticket_by_chk_contract AS ticket_by_chk_contract
            ON checklist_keyed.id_checklist_chk = ticket_by_chk_contract.id_checklist_chk
            AND checklist_keyed.id_contrato_con = ticket_by_chk_contract.id_contrato_con
    LEFT JOIN
        ticket_by_name_contract AS ticket_by_name_contract
            ON checklist_keyed.nome_chk_norm = ticket_by_name_contract.checklist_lookup_name
            AND checklist_keyed.id_contrato_con = ticket_by_name_contract.id_contrato_con
),
contract_side AS (
    SELECT
        'contrato' AS origem_checklist,
        checklist_resolved.id_checklist_cs,
        checklist_resolved.id_contrato_con,
        checklist_resolved.codigo_contrato,
        checklist_resolved.name_checklist,
        checklist_resolved.person_type,
        checklist_resolved.sub_item,
        checklist_resolved.sub_item_done,
        checklist_resolved.ts_sub_item_done AS dt_sub_item_done,
        checklist_resolved.dt_checklist_created,
        COALESCE(rollup_ticket.tipo, '') AS tipo_tkt,
        COALESCE(rollup_ticket.id_chave, '') AS id_chave,
        COALESCE(rollup_ticket.id_origem, '') AS id_origem_tkt,
        COALESCE(rollup_ticket.id_ticket_tic, '') AS id_ticket_tic,
        COALESCE(rollup_ticket.st_nome_usu, '') AS email_an_tkt,
        rollup_ticket.dt_inicioticket_tic AS dt_ini_tkt,
        rollup_ticket.dt_encerrado_tic AS dt_fin_tkt,
        CAST(NULL AS TIMESTAMP) AS dt_user_tkt,
        '' AS id_historico_mhis
    FROM
        checklist_resolved AS checklist_resolved
    LEFT JOIN
        datalake_benvi_manager_clean.benvi_rollup_ticket AS rollup_ticket
            ON checklist_resolved.nr_ordem_tkt = rollup_ticket.nr_ordem
),
historico_row AS (
    SELECT
        historico.id,
        TRIM(COALESCE(historico.id_manutencao_man, '')) AS id_manutencao_man,
        TRIM(COALESCE(historico.id_historico_mhis, '')) AS id_historico_mhis,
        COALESCE(historico.st_descricao_mhis, '') AS sub_item,
        COALESCE(historico.st_email_usu, '') AS email_an_tkt,
        historico.ts_data_mhis,
        CAST(
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(COALESCE(historico.id_manutencao_man, ''))
                ORDER BY historico.ts_data_mhis ASC NULLS LAST, historico.id
            ) AS INT
        ) AS count_checklist_cs
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_manutencao_historico AS historico
),
maintenance_side AS (
    SELECT
        'manutencao_historico' AS origem_checklist,
        CASE
            WHEN historico_row.id_manutencao_man <> ''
                THEN CONCAT_WS(
                    '-',
                    CAST(historico_row.count_checklist_cs AS STRING),
                    'MAN',
                    historico_row.id_manutencao_man
                )
            ELSE ''
        END AS id_checklist_cs,
        COALESCE(manutencao.id_contrato_con, '') AS id_contrato_con,
        COALESCE(contract_by_id.codigo_contrato, '') AS codigo_contrato,
        CASE
            WHEN TRIM(COALESCE(SPLIT(TRIM(REGEXP_REPLACE(
                TRIM(COALESCE(manutencao.st_descricao_man, '')), '(?i)^checklist\\s*-\\s*', ''
            )), ' :: ')[0], '')) <> ''
                THEN TRIM(COALESCE(SPLIT(TRIM(REGEXP_REPLACE(
                    TRIM(COALESCE(manutencao.st_descricao_man, '')), '(?i)^checklist\\s*-\\s*', ''
                )), ' :: ')[0], ''))
            WHEN TRIM(COALESCE(manutencao.st_categoria, '')) <> ''
                THEN CONCAT('[MAN] ', TRIM(manutencao.st_categoria))
            ELSE '[MAN] Manutencao'
        END AS name_checklist,
        CASE CAST(manutencao.fl_solicitante_man AS STRING)
            WHEN '1' THEN 'IQ'
            WHEN '2' THEN 'PP'
            ELSE 'INT'
        END AS person_type,
        historico_row.sub_item,
        '1' AS sub_item_done,
        historico_row.ts_data_mhis AS dt_sub_item_done,
        TO_DATE(manutencao.ts_criacao_man) AS dt_checklist_created,
        'manutencao' AS tipo_tkt,
        CASE
            WHEN historico_row.id_manutencao_man <> ''
                THEN CONCAT('manutencao-', historico_row.id_manutencao_man)
            ELSE ''
        END AS id_chave,
        historico_row.id_manutencao_man AS id_origem_tkt,
        '' AS id_ticket_tic,
        historico_row.email_an_tkt,
        manutencao.ts_criacao_man AS dt_ini_tkt,
        manutencao.ts_atualizacao_man AS dt_fin_tkt,
        CAST(NULL AS TIMESTAMP) AS dt_user_tkt,
        historico_row.id_historico_mhis
    FROM
        historico_row AS historico_row
    LEFT JOIN
        datalake_benvi_manager_clean.benvi_superlogica_manutencao AS manutencao
            ON historico_row.id_manutencao_man = TRIM(COALESCE(manutencao.id_manutencao_man, ''))
    LEFT JOIN
        contract_by_id AS contract_by_id
            ON TRIM(COALESCE(manutencao.id_contrato_con, '')) = contract_by_id.id_contrato_con
),
rollup_union AS (
    SELECT
        contract_side.origem_checklist,
        contract_side.id_checklist_cs,
        contract_side.id_contrato_con,
        contract_side.codigo_contrato,
        contract_side.name_checklist,
        contract_side.person_type,
        contract_side.sub_item,
        contract_side.sub_item_done,
        contract_side.dt_sub_item_done,
        contract_side.dt_checklist_created,
        contract_side.tipo_tkt,
        contract_side.id_chave,
        contract_side.id_origem_tkt,
        contract_side.id_ticket_tic,
        contract_side.email_an_tkt,
        contract_side.dt_ini_tkt,
        contract_side.dt_fin_tkt,
        contract_side.dt_user_tkt,
        contract_side.id_historico_mhis
    FROM
        contract_side AS contract_side
    UNION ALL
    SELECT
        maintenance_side.origem_checklist,
        maintenance_side.id_checklist_cs,
        maintenance_side.id_contrato_con,
        maintenance_side.codigo_contrato,
        maintenance_side.name_checklist,
        maintenance_side.person_type,
        maintenance_side.sub_item,
        maintenance_side.sub_item_done,
        maintenance_side.dt_sub_item_done,
        maintenance_side.dt_checklist_created,
        maintenance_side.tipo_tkt,
        maintenance_side.id_chave,
        maintenance_side.id_origem_tkt,
        maintenance_side.id_ticket_tic,
        maintenance_side.email_an_tkt,
        maintenance_side.dt_ini_tkt,
        maintenance_side.dt_fin_tkt,
        maintenance_side.dt_user_tkt,
        maintenance_side.id_historico_mhis
    FROM
        maintenance_side AS maintenance_side
)
SELECT
    rollup_union.origem_checklist,
    rollup_union.id_checklist_cs,
    rollup_union.id_contrato_con,
    rollup_union.codigo_contrato,
    rollup_union.name_checklist,
    rollup_union.person_type,
    rollup_union.sub_item,
    rollup_union.sub_item_done,
    rollup_union.dt_sub_item_done,
    rollup_union.dt_checklist_created,
    rollup_union.tipo_tkt,
    rollup_union.id_chave,
    rollup_union.id_origem_tkt,
    rollup_union.id_ticket_tic,
    rollup_union.email_an_tkt,
    rollup_union.dt_ini_tkt,
    rollup_union.dt_fin_tkt,
    rollup_union.dt_user_tkt,
    rollup_union.id_historico_mhis
FROM
    rollup_union AS rollup_union
