WITH base_phones AS (
    SELECT DISTINCT
        p.uuid_person,
        ci.contact_info AS phone
    FROM
        datalake_rental_guarantee_platform_clean.company co
    LEFT JOIN
        datalake_company_clean.company c
          ON c.uuid_company = co.uuid_company
    LEFT JOIN
        datalake_company_clean.member_profile mp
          ON c.id = mp.id_company
    LEFT JOIN
        datalake_person_clean.person p
          ON mp.uuid_person = p.uuid_person
    LEFT JOIN
        datalake_person_clean.contact_info ci
          ON p.id = ci.id_person
          AND ci.category = 'PHONE'
),
contact_info AS (
    SELECT DISTINCT
        b.id_broker,
        b.broker_name,
        b.broker_comercial_name,
        b.cnpj AS document,
        u.uuid_user AS id_realtor,
        u.name AS realtor,
        u.email,
        t.phone AS phone,
        u.user_role AS profile
    FROM
        datalake_velo.propose p
    LEFT JOIN
        datalake_velo.broker b
          ON b.id_broker = p.id_broker
    LEFT JOIN
        datalake_velo.user u
          ON u.id_user = p.id_agent
    LEFT JOIN
        base_phones t
          ON t.uuid_person = u.uuid_user
    WHERE
        u.user_role = 'admin'
),
realstate_production_timeline AS (
    SELECT
        b.id_broker,
        COUNT(DISTINCT CASE WHEN dt_contract_started IS NOT NULL THEN id_propose END) AS contracts,
        COUNT(DISTINCT CASE WHEN dt_contract_started IS NOT NULL AND dt_ended IS NULL THEN id_propose END) AS active_contracts,
        CAST(MIN(ts_propose_started) AS DATE) AS dt_imob_activation,
        MAX(dt_contract_started) AS last_contract
    FROM
        datalake_velo.propose pr
    LEFT JOIN
        datalake_velo.broker b
          ON pr.id_broker = b.id_broker
    GROUP BY
        b.id_broker
),
base_propose AS (
    SELECT
        id_propose_status,
        id_broker,
        id_propose,
        ts_propose_started,
        ts_paid,
        ts_secured,
        ts_signed,
        dt_contract_started,
        is_contract,
        dt_ended
    FROM
        datalake_velo.propose
    UNION ALL
    SELECT
        id_propose_status,
        id_broker,
        id_propose,
        ts_propose_started,
        ts_paid,
        ts_secured,
        ts_signed,
        dt_contract_started,
        is_contract,
        dt_ended
    FROM
        datalake_velo.propose_legacy
),
base AS (
    SELECT DISTINCT
        b.broker_name,
        b.broker_comercial_name,
        COALESCE(b.cnpj, cd.identification_number) AS cnpj,
        b.id_broker,
        b.city,
        b.state,
        b.is_broker_active,
        co.status AS status_broker,
        b.ts_created,
        pr.id_propose,
        pr.ts_propose_started,
        DATE(pr.ts_paid) AS dt_paid,
        DATE(pr.ts_secured) AS dt_secured,
        DATE(pr.ts_signed) AS dt_signed,
        pr.dt_contract_started,
        pr.is_contract,
        j.desc_lvl_1 AS desc_propose_status,
        pr.dt_ended,
        ia.dt_imob_activation,
        ia.contracts,
        ia.active_contracts,
        CASE
            WHEN j.desc_lvl_1 IN ('Reprovado pelo analista', 'Reprovado na análise humanizada') THEN 'Proposta não aprovada'
            WHEN j.desc_lvl_1 IN ('Análise humanizada', 'Mais documentos') THEN 'Documentos Pendentes'
            WHEN j.desc_lvl_1 = 'Análise de documentos' THEN 'Em análise humanizada'
            WHEN j.desc_lvl_1 = 'Mais proponentes' THEN 'Adicione corresponsáveis'
            WHEN j.desc_lvl_1 IN ('Aprovada pelo analista', 'Análise aprovada') THEN 'Aguardando assinatura e pagamento'
            WHEN j.desc_lvl_1 = 'Contrato Assinado mas não pago' THEN 'Assinado, aguardando pagamento'
            WHEN j.desc_lvl_1 = 'Contrato assinado e pago' THEN 'Contrato de locação pendente'
            WHEN j.desc_lvl_1 = 'Análise humana do contrato de locação' THEN 'Contrato de locação em análise'
            WHEN j.desc_lvl_1 = 'Reenviar contrato de aluguel' THEN 'Correção de dados pendente'
            WHEN j.desc_lvl_1 = 'Contrato aprovado' THEN 'Contrato ativo'
            WHEN j.desc_lvl_1 = 'Contrato Cancelado' THEN 'Contrato cancelado'
            WHEN j.desc_lvl_1 = 'Proposta Cancelada' THEN 'Proposta cancelada'
            ELSE 'Outros'
        END AS status_propose,
        p.person_name,
        ia.last_contract,
        potential_segmentation,
        credit_segmentation,
        r.rating
    FROM
        datalake_velo.broker b
    LEFT JOIN
        base_propose pr
          ON pr.id_broker = b.id_broker
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company co
          ON b.id_broker = co.id
    LEFT JOIN
        datalake_company_clean.document cd
          ON cd.uuid_company = co.uuid_company
          AND cd.document_type = 'CNPJ'
    LEFT JOIN
        datalake_velo.junk j
          ON pr.id_propose_status = j.id_junk
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_executive ce
          ON co.uuid_company = ce.uuid_company
          AND ce.is_active = true
    LEFT JOIN
        datalake_person_clean.person p
          ON p.uuid_person = ce.uuid_person
    LEFT JOIN
        datalake_gsheets_clean.quintocred_real_estates re
          ON CAST(re.sk_broker AS BIGINT) = b.id_broker
    LEFT JOIN
        realstate_production_timeline ia
          ON ia.id_broker = b.id_broker
    LEFT JOIN
        datalake_velo.neurotech_rating AS r
          ON r.id_propose = pr.id_propose
),
month_list AS (
    SELECT DISTINCT
        month_start,
        month_end
    FROM
        dw_public.dim_date
    WHERE
        date > '2019-01-01' AND date < CURRENT_DATE()
    ORDER BY month_start
),
timeline AS (
    SELECT
        *,
        CASE
            WHEN contracts = 0 THEN 'pre_active'
            WHEN contracts > 0 AND active_contracts = 0 THEN 'inactive'
            WHEN contracts > 0 AND active_contracts > 0 THEN 'active'
        END AS status_imob,
        CASE
            WHEN DATE_TRUNC('day', ts_propose_started) <= dd.month_end THEN 1
            ELSE 0
        END AS propose_exist_from_here,
        CASE
            WHEN (is_contract AND (dt_ended IS NULL OR DATE_TRUNC('month', dt_ended) >= DATE_TRUNC('month', dd.month_end))) THEN 1
            WHEN (NOT is_contract AND ts_propose_started >= dd.month_start) THEN 1
            ELSE 0
        END AS propose_exist_until_here,
        CASE
            WHEN DATE_TRUNC('month', ts_propose_started) = DATE_TRUNC('month', month_start) THEN TRUE
            ELSE FALSE
        END AS is_month_begin,
        CASE
            WHEN DATE_TRUNC('month', dt_ended) = DATE_TRUNC('month', month_start) THEN TRUE
            ELSE FALSE
        END AS is_month_end
    FROM
        base
    CROSS JOIN
        month_list dd
    ORDER BY
        id_propose, dd.month_start
),
timeline_adjusted AS (
    SELECT
        *
    FROM
        timeline
    WHERE
        propose_exist_from_here = 1
        AND propose_exist_until_here = 1
),
imob_aggregated AS (
    SELECT
        month_start AS month_ref,
        id_broker,
        dt_imob_activation,
        COUNT(DISTINCT CASE WHEN is_contract THEN id_propose END) AS contracts,
        COUNT(DISTINCT CASE WHEN is_month_begin THEN id_propose END) AS p_generated_at_month,
        COUNT(DISTINCT CASE WHEN is_contract AND is_month_begin THEN id_propose END) AS p2c_at_month,
        COUNT(DISTINCT CASE WHEN NOT is_contract AND is_month_begin THEN id_propose END) AS drop_p2c_at_month,
        COUNT(DISTINCT CASE WHEN is_contract AND is_month_begin AND is_month_end THEN id_propose END) AS contracts_beginning_and_ending_at_month,
        COUNT(DISTINCT CASE WHEN is_contract AND is_month_begin AND NOT is_month_end THEN id_propose END) AS contracts_beginning_at_month,
        COUNT(DISTINCT CASE WHEN is_contract AND is_month_end AND NOT is_month_begin THEN id_propose END) AS contracts_ending_at_month
    FROM
        timeline_adjusted
    GROUP BY
        month_ref, id_broker, dt_imob_activation
),
lagging_properties AS (
    SELECT *,
        LAG(p_generated_at_month, 1) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_1,
        LAG(p_generated_at_month, 2) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_2,
        LAG(p_generated_at_month, 3) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_3,
        LAG(p_generated_at_month, 4) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_4,
        LAG(p_generated_at_month, 5) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_5,
        LAG(p_generated_at_month, 6) OVER (PARTITION BY id_broker ORDER BY month_ref) AS proposes_gen_at_M_6,
        LAG(contracts_beginning_at_month, 1) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_1,
        LAG(contracts_beginning_at_month, 2) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_2,
        LAG(contracts_beginning_at_month, 3) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_3,
        LAG(contracts_beginning_at_month, 4) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_4,
        LAG(contracts_beginning_at_month, 5) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_5,
        LAG(contracts_beginning_at_month, 6) OVER (PARTITION BY id_broker ORDER BY month_ref) AS contracts_gen_at_M_6,
        12 * (YEAR(month_ref) - YEAR(dt_imob_activation)) + (MONTH(month_ref) - MONTH(dt_imob_activation)) AS mob_imob
    FROM imob_aggregated
),
final_base AS (
    SELECT
        *,
        proposes_gen_at_M_1 + proposes_gen_at_M_2 + proposes_gen_at_M_3 AS sum_proposes_gen_w3,
        proposes_gen_at_M_1 + proposes_gen_at_M_2 + proposes_gen_at_M_3 + proposes_gen_at_M_4 + proposes_gen_at_M_5 + proposes_gen_at_M_6 AS sum_proposes_gen_w6,
        contracts_gen_at_M_1 + contracts_gen_at_M_2 + contracts_gen_at_M_3 AS sum_contracts_gen_w3,
        contracts_gen_at_M_1 + contracts_gen_at_M_2 + contracts_gen_at_M_3 + contracts_gen_at_M_4 + contracts_gen_at_M_5 + contracts_gen_at_M_6 AS sum_contracts_gen_w6,
        (proposes_gen_at_M_1 + proposes_gen_at_M_2 + proposes_gen_at_M_3) / NULLIF(3, 0) AS avg_proposes_gen_w3,
        (proposes_gen_at_M_1 + proposes_gen_at_M_2 + proposes_gen_at_M_3 + proposes_gen_at_M_4 + proposes_gen_at_M_5 + proposes_gen_at_M_6) / NULLIF(6, 0) AS avg_proposes_gen_w6,
        (contracts_gen_at_M_1 + contracts_gen_at_M_2 + contracts_gen_at_M_3) / NULLIF(3, 0) AS avg_contracts_gen_w3,
        (contracts_gen_at_M_1 + contracts_gen_at_M_2 + contracts_gen_at_M_3 + contracts_gen_at_M_4 + contracts_gen_at_M_5 + contracts_gen_at_M_6) / NULLIF(6, 0) AS avg_contracts_gen_w6
    FROM lagging_properties
    WHERE id_broker IS NOT NULL AND id_broker <> -1 AND month_ref = DATE_TRUNC('month', CURRENT_DATE)
    ORDER BY month_ref
)
SELECT
    f.id_broker,
    f.id_realtor,
    f.broker_name,
    f.broker_comercial_name,
    f.document,
    f.realtor,
    f.email,
    f.phone,
    f.profile,
    m.contracts,
    m.p_generated_at_month,
    m.p2c_at_month,
    m.drop_p2c_at_month,
    m.contracts_beginning_and_ending_at_month,
    m.contracts_beginning_at_month,
    m.contracts_ending_at_month,
    m.proposes_gen_at_M_1,
    m.proposes_gen_at_M_2,
    m.proposes_gen_at_M_3,
    m.proposes_gen_at_M_4,
    m.proposes_gen_at_M_5,
    m.proposes_gen_at_M_6,
    m.contracts_gen_at_M_1,
    m.contracts_gen_at_M_2,
    m.contracts_gen_at_M_3,
    m.contracts_gen_at_M_4,
    m.contracts_gen_at_M_5,
    m.contracts_gen_at_M_6,
    m.sum_proposes_gen_w3,
    m.sum_proposes_gen_w6,
    m.sum_contracts_gen_w3,
    m.sum_contracts_gen_w6,
    m.avg_proposes_gen_w3,
    m.avg_proposes_gen_w6,
    m.avg_contracts_gen_w3,
    m.avg_contracts_gen_w6,
    CASE
        WHEN (m.proposes_gen_at_M_1 + m.proposes_gen_at_M_2) > 0 THEN 'nps_true'
        WHEN (m.proposes_gen_at_M_1 + m.proposes_gen_at_M_2) = 0 THEN 'nps_lost'
    END AS nps_type,
    m.mob_imob,
    m.dt_imob_activation,
    m.month_ref AS dt_reference
FROM
    final_base m
LEFT JOIN
    contact_info f ON CAST(f.id_broker AS INT) = CAST(m.id_broker AS INT)
WHERE
    ((m.proposes_gen_at_M_1 + m.proposes_gen_at_M_2) > 0 AND f.email IS NOT NULL)
    OR ((m.proposes_gen_at_M_1 + m.proposes_gen_at_M_2) = 0 AND f.email IS NOT NULL AND m.mob_imob > 3)
