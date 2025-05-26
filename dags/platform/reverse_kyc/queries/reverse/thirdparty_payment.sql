WITH pagamentos_base AS (
    SELECT 
        CAST(regexp_extract(company_use, '^(.*?)T', 1) AS BIGINT) AS contrato,
        due_amount,
        occurrence_reason,
        Payee_name,
        payee_document,
        dt_paid
    FROM datalake_vans_clean.Payment
    WHERE 
        Requested_by = 'seubarriga'
        AND status = ':payment.status/paid'
        AND dt_paid > DATE '2025-04-01'
),

pagamentos AS (
    SELECT *
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY contrato, payee_document, dt_paid, due_amount ORDER BY occurrence_reason) AS rn
        FROM pagamentos_base
    ) sub
    WHERE rn = 1
),

pp_contrato AS (
    SELECT
        fcp.sk_contract AS contrato,
        fcp.sk_user,
        dcp.full_name AS nome_pp,
        fcp.sk_personal_document AS cpf_pp,
        MAX(doc.is_pp_multi) AS is_pp_multi
    FROM dw_rent.fact_contract_people fcp
    LEFT JOIN dw_rent.dim_contract_person dcp 
        ON dcp.sk_contract_person = fcp.sk_contract_person
    LEFT JOIN dw_rent.dim_owner_category doc
        ON doc.sk_owner = fcp.sk_user
    WHERE fcp.contract_role = 'landlord'
    GROUP BY fcp.sk_contract, fcp.sk_user, dcp.full_name, fcp.sk_personal_document
),

qtd_pps_por_contrato AS (
    SELECT 
        fcp.sk_contract AS contrato,
        COUNT(DISTINCT fcp.sk_personal_document) AS qtd_pps
    FROM dw_rent.fact_contract_people fcp
    WHERE fcp.contract_role = 'landlord'
    GROUP BY fcp.sk_contract
),

pagamentos_vs_pps_raw AS (
    SELECT 
        p.*,
        pp.sk_user,
        pp.nome_pp,
        pp.cpf_pp,
        pp.is_pp_multi,
        REGEXP_REPLACE(p.payee_document, '[^0-9]', '') AS doc_recebedor,
        REGEXP_REPLACE(pp.cpf_pp, '[^0-9]', '') AS doc_pp,
        CASE 
            WHEN REGEXP_REPLACE(p.payee_document, '[^0-9]', '') = REGEXP_REPLACE(pp.cpf_pp, '[^0-9]', '') 
            THEN 1 ELSE 0 
        END AS documento_bate
    FROM pagamentos p
    LEFT JOIN pp_contrato pp ON p.contrato = pp.contrato
),

documento_bate_resumo AS (
    SELECT 
        contrato, 
        dt_paid, 
        MAX(
            CASE 
                WHEN REGEXP_REPLACE(payee_document, '[^0-9]', '') = REGEXP_REPLACE(cpf_pp, '[^0-9]', '') 
                THEN 1 ELSE 0 
            END
        ) AS documento_bate_com_algum_pp
    FROM pagamentos_vs_pps_raw
    GROUP BY contrato, dt_paid
)

SELECT 
    pvp.contrato,
    pvp.dt_paid,
    pvp.due_amount,
    pvp.occurrence_reason,
    pvp.Payee_name AS nome_recebedor,
    pvp.payee_document AS documento_recebedor,
    pvp.sk_user AS sk_pp,
    pvp.nome_pp,
    pvp.cpf_pp AS documento_pp,
    qtd.qtd_pps,
    pvp.is_pp_multi,
    CASE 
        WHEN resumo.documento_bate_com_algum_pp = 1 THEN '✅ Documento bate com algum PP'
        ELSE '❌ Documento diferente de todos os PPs'
    END AS status_validacao
FROM pagamentos_vs_pps_raw pvp
LEFT JOIN qtd_pps_por_contrato qtd ON pvp.contrato = qtd.contrato
LEFT JOIN documento_bate_resumo resumo 
  ON pvp.contrato = resumo.contrato AND pvp.dt_paid = resumo.dt_paid
WHERE resumo.documento_bate_com_algum_pp <> 1
ORDER BY pvp.contrato, pvp.dt_paid, pvp.nome_pp