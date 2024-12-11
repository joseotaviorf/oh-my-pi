WITH contract AS (
    SELECT DISTINCT
        cp.id_contract,
        cp.id_contract_person,
        COALESCE(cp.id_user_contract_person,ebdb_cpf.id,ebdb_email.id) AS id_user,
        cp.contract_role
    FROM
        datalake_ebdb_contract.contract_person cp
    LEFT JOIN
        datalake_ebdb_user.user AS ebdb_cpf
            ON cp.personal_document = ebdb_cpf.cpf
    LEFT JOIN
        datalake_ebdb_user.user AS ebdb_email
            ON SPLIT(cp.email,';',1) = SPLIT(ebdb_email.email,';',1)
    WHERE
        COALESCE(cp.id_user_contract_person,ebdb_cpf.id,ebdb_email.id) > 0
        AND COALESCE(cp.id_user_contract_person,ebdb_cpf.id,ebdb_email.id) IS NOT NULL
        AND cp.contract_role IN ('tenant','landlord')
),
customer_support_cte AS (
    SELECT DISTINCT
        MAX(t.id_user_main) AS id_user,
        CAST(t.id_ticket AS BIGINT) AS id_ticket,
        t.front_or_back,
        t.last_queue AS department,
        cs.last_csat_score AS csat,
        t.ts_created AS ts_created_local
    FROM
        datalake_customer_support.tickets AS t
    LEFT JOIN
        datalake_customer_support.csat AS cs
            ON cs.id_ticket = t.id_ticket
    LEFT JOIN
        datalake_gsheets_clean.department_control AS dc
            ON dc.department = t.last_queue
    WHERE
        t.id_user_main > 0
        AND dc.journey_step = 'Offboarding'
        AND t.ts_created >= '2021-01-01'
        AND t.channel = 'cs email'
    GROUP BY ALL
)
SELECT
    ong.id_contract,
    cs.department,
    cs.front_or_back,
    COUNT(DISTINCT
        CASE
            WHEN cs.csat >= 4 THEN cs.id_ticket
            ELSE NULL
        END
    ) AS num_ticket_satisfied,
    COUNT(DISTINCT
        CASE
            WHEN cs.csat = 3 THEN cs.id_ticket
            ELSE NULL
        END
    ) AS num_ticket_neutral,
    COUNT(DISTINCT
        CASE
            WHEN cs.csat <= 2 THEN cs.id_ticket
            ELSE NULL
        END
    ) AS num_ticket_dissatisfied
FROM
    datalake_offboarding.ongoing ong
LEFT JOIN
    contract AS ctr
        ON ctr.id_contract = ong.id_contract
LEFT JOIN
    customer_support_cte cs
        ON cs.id_user = ctr.id_user
        AND cs.ts_created_local > ong.ts_termination_request
        AND cs.ts_created_local <= COALESCE(ong.ts_termination_finished, CURRENT_DATE())
GROUP BY
    1,2,3
