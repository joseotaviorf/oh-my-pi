WITH trato_feito AS (
    SELECT DISTINCT
        CAST(i.id AS STRING) AS id_payment_platform,
        n.id_debtor_external AS id_business_entity,
        ai.id_external AS id_finance_entity,
        'trato-feito' AS payment_platform,
        p.status AS payment_status,
        NULL AS reference_1,
        NULL AS reference_2,
        NULL AS reference_3,
        NULL AS reference_4,
        NULL AS reference_5,
        CAST(p.metadata:paid_amount AS DOUBLE) AS paid_amount,
        CAST(SPLIT(p.metadata:paid_date, 'T')[0] AS DATE) AS dt_paid,
        CAST(SPLIT(p.metadata:paid_date, 'T')[0] AS DATE) AS dt_receipt
    FROM
        datalake_trato_feito_clean.negotiation n
    INNER JOIN
        datalake_trato_feito_clean.installment i
            ON n.id = i.id_negotiation
    INNER JOIN
        datalake_trato_feito_clean.accounting_installment ai
            ON ai.id_installment = i.id
    LEFT JOIN
        datalake_trato_feito_clean.payment p
            ON p.id_installment = i.id
),

wallstreet AS (
    SELECT DISTINCT
        CAST(id as STRING) as id_payment_platform,
        c.id_business_entity,
        id_finance_entity,
        'wallstreet' as payment_platform,
        charge_status as payment_status,
        NULL AS reference_1,
        NULL AS reference_2,
        NULL AS reference_3,
        NULL AS reference_4,
        NULL AS reference_5,
        CAST(amount/100.00 AS DOUBLE) AS paid_amount,
        CAST(c.ts_paid AS DATE) AS dt_paid,
        CAST(c.ts_paid AS DATE) AS dt_receipt
    FROM
        datalake_wall_street_clean.charge c
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY c.id_finance_entity ORDER BY c.ts_updated DESC) = 1
),

robin_hood AS (
    SELECT DISTINCT
        CAST(ae.id AS STRING) AS id_payment_platform,
        NULL AS id_business_entity,
        ae.id_external AS id_finance_entity,
        'robin-hood' AS payment_platform,
        pr.status AS payment_status,
        NULL AS reference_1,
        NULL AS reference_2,
        NULL AS reference_3,
        NULL AS reference_4,
        NULL AS reference_5,
        ae.due_amount AS paid_amount,
        pr.dt_paid,
        dt_paid AS dt_receipt
    FROM
        datalake_robin_hood.accounting_entry ae
    LEFT JOIN
        datalake_robin_hood_clean.accounting_entry_balance eb
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN
        datalake_robin_hood_clean.payment_request pr
            ON pr.id = eb.id_payment_request
    WHERE
        source_bill_item = 'estate-agent-services'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ae.id_external ORDER BY pr.ts_created DESC) = 1
),

vans AS (
WITH boleto_file_response AS (
    SELECT
        id
    FROM
        datalake_vans_clean.file f
    WHERE
        f.type =':file.type/boleto'
        AND f.origin = ':file.origin/response'
),

next_business_day AS (
    SELECT
        dd.date,
        MIN(dd_next.date) AS date_next_bd
    FROM
        dw_public.dim_date AS dd
    LEFT JOIN
        dw_public.dim_date AS dd_next
            ON dd_next.working_days_in_month <> dd.working_days_in_month
            AND dd_next.date > dd.date
            AND dd_next.working_days_in_month > 0
    GROUP BY
        1
),

CAP AS (
    SELECT
        c.id AS id_payment_platform,
        SPLIT(c.company_use, '[a-zA-Z!]')[0] AS id_business_entity,
        id_related_document AS id_finance_entity,
        'vans_cap' AS payment_platform,
        status as payment_status,
        c.company_use AS reference_1,
        our_number AS reference_2,
        CASE
            WHEN UPPER(pagamento) LIKE 'PROTEÇÃO 5A%' AND UPPER(our_number) LIKE 'MANUAL%' THEN 'Repasse Extra'
            WHEN UPPER(pagamento) LIKE 'PROTEÇÃO 5A%' THEN 'Repasse Extra'
            WHEN UPPER(pagamento) LIKE '%3P%' THEN 'Imobiliarias 3P'
            WHEN UPPER(pagamento) LIKE 'CONDOM%' THEN 'Condomínio'
            WHEN UPPER(pagamento) LIKE 'ANTECIPA%' THEN 'MRA'
            WHEN UPPER(pagamento) LIKE 'CIQ%' THEN 'CIQ'
            WHEN UPPER(pagamento) LIKE 'PP não residente' THEN 'PP não residente'
            WHEN UPPER(pagamento) LIKE 'ONG%' THEN 'Aluguel'
            WHEN UPPER(pagamento) LIKE 'Aporte FIDC' THEN 'Aporte FIDC'
            WHEN regexp_like(UPPER(pagamento),'^DEVOLUÇÃO|^EXTRA') THEN 'Repasse Extra'
            WHEN regexp_like(UPPER(pagamento),'^MULTA RESCISÓRIA|^CONTAS DE CONSUMO|^ALUGUEL|^CORRETORES|^IPTU|^REPASSE B2B|^BAND-AID|^CRÉDITO A SALDAR|^EARLY TERMINATION|^MRA|^REPASSES EXTRAS|^REPASSES BAND-AID|^CONDOMÍNIO DEPÓSITO|^ALUGUEL MANUAL|^CORRETOR 3P|^ONGOING MANUAL|^B2B|^CONTAS DE CONSUMO|^NÃO PROTEÇÃO|^REEMBOLSO') THEN pagamento
            ELSE NULL
        END AS reference_3,
        TipoPagamento AS reference_4,
        CONCAT(id_bank_payment, ":", name) AS reference_5,
        paid_amount,
        dt_paid,
        dt_paid AS dt_receipt
    FROM
        (SELECT
          p.id,
          id_related_document,
          p.our_number,
          p.company_use,
          SPLIT(p.status, '/')[1] AS status,
          p.dt_paid,
          IF(status = ':payment.status/chargeback', p.paid_amount, p.paid_amount*(-1)) AS paid_amount,
          p.requested_by,
          p.id_bank_payment,
          p.ts_updated,
          CASE
                WHEN p.requested_by = 'sb-corretores' THEN 'Corretores'
                WHEN p.requested_by = 'rh-corretores' THEN 'Corretores'
                WHEN p.requested_by in ('indica-ai', 'indica-ai-agents') THEN 'IndicaAi'
                WHEN p.requested_by = 'rh-porteiros' THEN 'Porteiros'
                WHEN p.requested_by = 'rh-ciq' THEN 'CIQ'
                WHEN p.requested_by = 'executive-for-rent' THEN 'CIQ Select'
                WHEN p.requested_by = 'ciq-captacao' THEN 'CIQ Captação'
                WHEN p.requested_by = 'imobs-for-rent' THEN 'Imobiliarias 3P'
                WHEN regexp_like((p.company_use), '^[0-9]+T[0-9]+$') THEN 'Aluguel'
                WHEN regexp_like((p.company_use), '^[0-9]+I[0-9]+$') THEN 'Crédito a Saldar'
                WHEN regexp_like((p.company_use), '^[0-9]+L[0-9]+$') THEN 'Multa rescisória'
                WHEN regexp_like((p.company_use), '^[0-9]+R[0-9]+$') THEN 'Early termination'
                WHEN regexp_like((p.company_use), '^[0-9]+!MO[0-9]+$') THEN 'Ongoing'
                WHEN regexp_like((p.company_use), '^[0-9]+Corretor$') THEN 'Corretores'
                WHEN regexp_like((p.company_use), '^[0-9]+BAI[0-9]+$') THEN 'Band-Aid'
                WHEN regexp_like((p.company_use), '^[0-9]+BAP[0-9]+$') THEN 'Band-Aid'
                WHEN regexp_like((p.company_use), '^[0-9]+MR[0-9]+$') THEN 'MRA'
                WHEN regexp_like((p.company_use), '^[0-9]+RBI[0-9]+$') THEN 'Reembolso'
                WHEN regexp_like((p.company_use), '^[0-9]+RBP[0-9]+$') THEN 'Reembolso'
                WHEN regexp_like((p.company_use), '^[0-9]+EI[0-9]+$') THEN 'Repasses Extras'
                WHEN regexp_like((p.company_use), '^[0-9]+EP[0-9]+$') THEN 'Repasses Extras'
                WHEN regexp_like((p.company_use), '^[0-9]+NPP[0-9]+$') THEN 'Não Proteção'
                WHEN regexp_like((p.company_use), '^[0-9]+NPI[0-9]+$') THEN 'Não Proteção'
                WHEN regexp_like((p.company_use), '^[0-9]+BA[0-9]+$') THEN 'BandAid'
                WHEN regexp_like((p.company_use), '^[0-9]+CI[0-9]+$') THEN 'Conciliação'
                WHEN regexp_like((p.company_use), '^[0-9]+CP[0-9]+$') THEN 'Conciliação'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MBD[0-9]+$') AND dt_paid >= '2024-02-05'THEN 'Band-Aid'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+ME[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Repasses Extras'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MC[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Repasses Band-Aid'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MCP[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Condomínio Depósito'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MA[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'MRA'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MT[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Aluguel Manual'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MC3P[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Corretor 3P'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MO[0-9]+$') AND dt_paid >= '2024-02-05' THEN 'Ongoing Manual'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MB[0-9]+$') AND dt_paid <= '2024-02-19' THEN 'Band-Aid'
                WHEN regexp_like((p.company_use), '^[0-9]+![0-9]+MB[0-9]+$') AND dt_paid > '2024-02-19' THEN 'B2B'
            END AS pagamento,
        CASE
            WHEN p.style='05' THEN 'Crédito em Conta Poupança'
            WHEN p.style='01' THEN 'Crédito em Conta Corrente'
            WHEN p.style='41' THEN 'TED'
            WHEN p.style='03' THEN 'DOC'
            ELSE p.style
        END AS TipoPagamento
        FROM
            datalake_vans_clean.payment p
        INNER JOIN
            datalake_vans_clean.file_payment fp
                ON fp.id_payment = p.id
        INNER JOIN
            datalake_vans_clean.file f
                ON f.id = fp.id_file
        WHERE
            p.dt_paid >= '2022-12-01'
        AND
            f.type=':file.type/payment.csv'
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY company_use ORDER BY f.ts_created DESC) = 1

        UNION ALL

        SELECT
          pb.id,
          id_related_document,
          pb.our_number,
          pb.company_use,
          SPLIT(pb.status, '/')[1] as status,
          pb.dt_paid,
          pb.paid_amount*(-1) as paid_amount,
          pb.requested_by,
          CAST((if(pb.id_bank_payment = null, '0', '1')) AS decimal(20,0)) as id_bank_payment,
          pb.ts_updated,
          CASE
            WHEN pb.company_use = '00000000000000000000' THEN null
            WHEN regexp_like((company_use),'^[0-9]+P[0-9]+$') THEN 'Condomínio V8'
            WHEN regexp_like((company_use),'^00000000000000+[0-9]+$') THEN 'Condomínio V9'
            WHEN regexp_like((company_use),'^[0-9]+![0-9]+MC[0-9]+$') THEN 'Condominio v9'
            WHEN regexp_like((company_use),'^[0-9]+![0-9]+MT[0-9]+$') THEN 'Aluguel Manual'
            WHEN regexp_like((company_use),'^[0-9]+![0-9]+MCD[0-9]+$') THEN 'Condominio v9 - Despejo'
            WHEN regexp_like((company_use),'REFERA+!MO[0-9]+$') THEN 'Ongoing - Boleto'
            WHEN regexp_like((company_use),'^[0-9]+![0-9]+MCCM[0-9]+$') AND ts_updated >= '2024-02-06' THEN 'Contas de Consumo'
          END as pagamento,
        CASE
            WHEN pb.style='05' THEN 'Crédito em Conta Poupança'
            WHEN pb.style='01' THEN 'Crédito em Conta Corrente'
            WHEN pb.style='41' THEN 'TED'
            WHEN pb.style='03' THEN 'DOC'
            ELSE pb.style
        END as TipoPagamento
        FROM
            datalake_vans_clean.payment_boleto pb
        WHERE
            pb.dt_paid >= '2022-12-01'
        ) c
      LEFT JOIN
          datalake_vans_clean.bank_payment bp
              ON c.id_bank_payment = bp.id
      LEFT JOIN
          datalake_vans_clean.bank b
              ON bp.id_bank = b.id
)

SELECT
    *
FROM
    CAP

UNION ALL

SELECT
    CAST(b.id AS STRING) as id_payment_platform,
    SPLIT(b.company_use, '[a-zA-Z!]')[0] AS id_business_entity,
    b.id_related_document AS id_finance_entity,
    'vans_car' AS payment_platform,
    SPLIT(b.status, "/")[1] AS payment_status,
    b.company_use AS reference_1,
    b.our_number AS reference_2,
    NULL AS reference_3,
    NULL AS reference_4,
    NULL AS reference_5,
    b.paid_amount AS payment_amount,
    b.dt_paid,
    nbd.date_next_bd AS dt_receipt
FROM
    datalake_vans_clean.boleto b
INNER JOIN
    datalake_vans_clean.boleto_file bf
        ON b.id = bf.id_boleto
INNER JOIN
    boleto_file_response bfr
        ON bfr.id = bf.id_file
LEFT JOIN
    next_business_day AS nbd
        ON nbd.date = b.dt_paid
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY b.id_related_document ORDER BY b.ts_updated DESC) = 1
)

SELECT
    *
FROM
    trato_feito
UNION ALL
SELECT
    *
FROM
    wallstreet
UNION ALL
SELECT
    *
FROM
    robin_hood
UNION ALL
SELECT
    *
FROM
    vans
