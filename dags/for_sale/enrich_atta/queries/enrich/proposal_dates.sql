WITH log_union AS (
    (
        SELECT
            CAST(id AS STRING) AS id,
            id_proposal,
            id_current_status,
            id_current_proposal_situation,
            ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v1
    )
    UNION
    (
        SELECT
            id,
            CAST(id_proposal AS INTEGER) AS id_proposal,
            CAST(GET_JSON_OBJECT(to, '$.Status') AS INTEGER) AS id_current_status,
            CAST(GET_JSON_OBJECT(to, '$.Situacao') AS INTEGER) AS id_current_proposal_situation,
            CAST(GET_JSON_OBJECT(to, '$.DtUltAtu') AS TIMESTAMP) AS ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v2
        WHERE
            GET_JSON_OBJECT(to, '$.Status') IS NOT NULL
            AND type_operation = 'Proposta'
    )
),
log_classified AS (
    SELECT
        log.id_proposal,
        pre.proposal_status AS track_step,
        case log.id_current_proposal_situation
            when 1 then 'Andamento'
            when 2 then 'Aprovado'
            when 3 then 'Pendente'
            when 4 then 'Reprovado'
            when 5 then 'Cancelada'
            when 6 then 'Finalizada'
            when 7 then 'Em Análise'
            when 8 then 'Análise Atta'
            when 9 then 'Análise Banco'
            when 10 then 'Análise Banco Duvida'
        end AS track_detail,
        log.ts_current_log AS ts_log,
        MIN(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS min_ts_step,
        MAX(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS max_ts_step
    FROM
        log_union AS log
    LEFT JOIN
        datalake_atta_clean.proposal AS pp
            ON pp.id_proposal = log.id_proposal
    LEFT JOIN
        datalake_atta_clean.track_step_detail AS pre
            ON pre.decision_number = log.id_current_status
            AND pre.id_product = pp.id_product
)
SELECT
    id_proposal,
    MIN(
        CASE
            WHEN track_step = 'Carta de Crédito' THEN min_ts_step
        END
    ) AS ts_credit_started,
--get the least of two columns considering NULL values presence >> LEAST() formula returns NULL if any value is NULL
    CASE
        --both values are NULL then return NULL
        WHEN
            MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ) IS NULL
            AND
            MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) IS NULL
                THEN NULL
        --only Vistoria is NULL then return Checklist
        WHEN
            MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ) IS NULL
                THEN MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END )
        --only Checklist is NULL then return Vistoria
        WHEN
            MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) IS NULL
                THEN MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END )
        --least of Vistoria and Checklist without NULL values cases
        ELSE
            LEAST(MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ), MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) )
    END AS ts_credit_ended,
--get the least of two columns considering NULL values presence >> LEAST() formula returns NULL if any value is NULL
    CASE
        --both values are NULL then return NULL
        WHEN
            MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ) IS NULL
            AND
            MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) IS NULL
                THEN NULL
        --only Vistoria is NULL then return Checklist
        WHEN
            MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ) IS NULL
                THEN MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END )
        --only Checklist is NULL then return Vistoria
        WHEN
            MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) IS NULL
                THEN MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END )
        --least of Vistoria and Checklist without NULL values cases
        ELSE
            LEAST(MIN( CASE WHEN track_step = 'Vistoria' THEN min_ts_step END ), MIN( CASE WHEN track_step = 'Checklist' THEN min_ts_step END ) )
    END AS ts_financing_started,
    MIN(
        CASE
            WHEN track_step = 'Contratação'
                THEN min_ts_step
        END
    ) AS ts_bank_legal_analysis_started,
    MIN(
        CASE
            WHEN track_step = 'Conf / Emissão'
                THEN min_ts_step
        END
    ) AS ts_bank_legal_analysis_ended,
    MAX(
        CASE
            WHEN track_step = 'Conf / Emissão' AND track_detail = 'Aprovado'
                THEN ts_log
        END
    ) AS ts_last_approved_log,
    MIN(
        CASE
            WHEN track_detail IN ('Reprovado', 'Cancelada')
                THEN ts_log
        END
    ) AS ts_first_cancelation,
    MAX(
        CASE
            WHEN track_detail IN ('Reprovado', 'Cancelada')
                THEN ts_log
        END
    ) AS ts_last_cancelation,
    MIN(
        CASE
            WHEN track_step = 'Pré - Análise'
                THEN min_ts_step
        END
    ) AS ts_min_pre_analysis,
    MIN(
        CASE
            WHEN track_step = 'Pré - Análise'
                THEN max_ts_step
        END
    ) AS ts_max_pre_analysis,
    MIN(
        CASE
            WHEN track_step = 'Carta de Crédito'
                THEN min_ts_step
        END
    ) AS ts_min_credit_application,
    MIN(
        CASE
            WHEN track_step = 'Carta de Crédito'
                THEN max_ts_step
        END
    ) AS ts_max_credit_application,
    MIN(
        CASE
            WHEN track_step = 'Carta de Crédito' AND track_detail = 'Aprovado'
                THEN ts_log
        END
    ) AS ts_min_credit_application_approval,
    MAX(
        CASE
            WHEN track_step = 'Carta de Crédito' AND track_detail = 'Aprovado'
                THEN ts_log
        END
    ) AS ts_max_credit_application_approval,
    MIN(
        CASE
            WHEN track_step = 'Carta de Crédito' AND track_detail = 'Reprovado'
                THEN ts_log
        END
    ) AS ts_min_credit_application_reproval,
    MAX(
        CASE
            WHEN track_step = 'Carta de Crédito' AND track_detail = 'Reprovado'
                THEN ts_log
        END
    ) AS ts_max_credit_application_reproval,
    MIN(
        CASE
            WHEN track_step = 'Vistoria'
                THEN min_ts_step
        END
    ) AS ts_min_inspection,
    MIN(
        CASE
            WHEN track_step = 'Vistoria'
                THEN max_ts_step
        END
    ) AS ts_max_inspection,
    MIN(
        CASE
            WHEN track_step = 'Checklist'
                THEN min_ts_step
        END
    ) AS ts_min_checklist,
    MIN(
        CASE
            WHEN track_step = 'Checklist'
                THEN max_ts_step
        END
    ) AS ts_max_checklist,
    MIN(
        CASE
            WHEN track_step = 'Contratação'
                THEN min_ts_step
        END
    ) AS ts_min_bank_application,
    MIN(
        CASE
            WHEN track_step = 'Contratação'
                THEN max_ts_step
        END
    ) AS ts_max_bank_application,
    MIN(
        CASE
            WHEN track_step = 'Conf / Emissão'
                THEN min_ts_step
        END
    ) AS ts_min_financing_contract,
    MIN(
        CASE
            WHEN track_step = 'Conf / Emissão'
                THEN max_ts_step
        END
    ) AS ts_max_financing_contract,
    MIN(
        CASE
            WHEN track_step = 'Contratado'
                THEN min_ts_step
        END
    ) AS ts_min_contracted,
    MIN(
        CASE
            WHEN track_step = 'Contratado'
                THEN max_ts_step
        END
    ) AS ts_max_contracted
FROM
    log_classified
GROUP BY
    id_proposal
