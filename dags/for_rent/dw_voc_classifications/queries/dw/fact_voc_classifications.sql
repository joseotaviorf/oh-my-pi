WITH vocs AS (
    SELECT
        id_feedback,
        id_prompt,
        id_author,
        id_account,
        prompt_hash,
        feedback_kind,
        source_name,
        customer_type,
        campaign_name,
        rating,
        is_label,
        ts_submitted,
        ts_classified,
        year,
        month,
        day
    FROM
        datalake_vocs_machina_clean.vocs_machina
),

csat_feedback_keys AS (
    SELECT DISTINCT id_feedback
    FROM
        vocs
    WHERE
        feedback_kind = 'csat'
),

survicate_dedup AS (
    SELECT
        sr.id_response,
        sr.response_url,
        COALESCE(
            PARSE_URL(sr.response_url, 'QUERY', 'ticket_id'),
            PARSE_URL(sr.response_url, 'QUERY', 't_id')
        ) AS ticket_id,
        ROW_NUMBER() OVER (
            PARTITION BY sr.id_response
            ORDER BY sr.dt_load DESC
        ) AS rn
    FROM
        datalake_survicate.survey_responses AS sr
    INNER JOIN
        csat_feedback_keys AS cfk
        ON sr.id_response = cfk.id_feedback
),

survicate_responses AS (
    SELECT
        id_response,
        response_url,
        ticket_id
    FROM
        survicate_dedup
    WHERE
        rn = 1
),

referenced_ticket_ids AS (
    SELECT DISTINCT TRY_CAST(ticket_id AS BIGINT) AS sk_ticket
    FROM
        survicate_responses
    WHERE
        ticket_id IS NOT NULL
        AND TRY_CAST(ticket_id AS BIGINT) IS NOT NULL
),

tickets AS (
    SELECT
        ft.sk_ticket,
        ft.sk_contract
    FROM
        dw_customer_support.fact_tickets AS ft
    INNER JOIN
        referenced_ticket_ids AS rti
        ON ft.sk_ticket = rti.sk_ticket
),

classified AS (
    SELECT
        vm.id_feedback,
        vm.id_prompt,
        vm.prompt_hash,
        vm.feedback_kind,
        vm.source_name,
        vm.customer_type,
        vm.campaign_name,
        vm.rating,
        vm.is_label,
        vm.ts_submitted,
        vm.ts_classified,
        vm.year,
        vm.month,
        vm.day,
        CASE
            WHEN
                vm.feedback_kind = 'nps'
                AND vm.source_name IN ('ongoing', 'offboarding', 'onboarding', 'pp_multi')
                AND vm.id_account RLIKE '^[0-9]+_(tenant|landlord)$'
                THEN TRY_CAST(SPLIT(vm.id_account, '_')[0] AS BIGINT)
            WHEN vm.feedback_kind = 'csat'
                THEN COALESCE(
                    NULLIF(
                        NULLIF(TRY_CAST(PARSE_URL(sr.response_url, 'QUERY', 'contractid') AS BIGINT), -1),
                        0
                    ),
                    NULLIF(NULLIF(t.sk_contract, -1), 0)
                )
        END AS sk_contract,
        TRY_CAST(vm.id_author AS BIGINT) AS sk_user,
        BIGINT(DATE_FORMAT(vm.ts_submitted, 'yyyyMMdd')) AS sk_submitted_date
    FROM
        vocs AS vm
    LEFT JOIN
        survicate_responses AS sr
        ON vm.id_feedback = sr.id_response
    LEFT JOIN
        tickets AS t
        ON TRY_CAST(sr.ticket_id AS BIGINT) = t.sk_ticket
)

SELECT
    id_feedback,
    id_prompt,
    prompt_hash,
    sk_contract,
    sk_user,
    feedback_kind,
    source_name,
    customer_type,
    campaign_name,
    rating,
    is_label,
    sk_submitted_date,
    ts_submitted,
    ts_classified,
    year,
    month,
    day
FROM
    classified
