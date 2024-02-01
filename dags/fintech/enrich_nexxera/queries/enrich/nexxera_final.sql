
-- START | SETUP STANDARD
WITH JDT_NUM AS (
    SELECT ROW_NUMBER() OVER(ORDER BY dt_credit, id_flag, ec, id_external_payment) AS JdtNum,
        dt_credit AS TaxDate,
        id_flag,
        ec,
        id_external_payment
    FROM
        datalake_nexxera.nexxera_base
    GROUP BY dt_credit,
        id_flag,
        ec,
        id_external_payment
    ORDER BY
        1
),
JDT_A AS (
    SELECT ROW_NUMBER() OVER(ORDER BY eb.dt_credit) AS rn_jdt1,
        jn.JdtNum,
        jn.TaxDate,
        bb.launch_value,
        eb.*
    FROM
        datalake_nexxera.nexxera_base eb
    LEFT JOIN
        JDT_NUM jn
        ON jn.TaxDate = eb.dt_credit
        AND jn.id_external_payment = eb.id_external_payment
    LEFT JOIN
        datalake_nexxera.financial_extracts_050e bb
        ON bb.dt_launch = jn.TaxDate
        AND bb.id_ec = jn.ec
        AND bb.id_flag = jn.id_flag
),
-- END | SETUP STANDARD

-- START | PRODUCT BLOCK
PAYMENTS_INSTALLMENT_VELO AS ( -- HELPER CTE
    SELECT
        ROW_NUMBER() OVER (PARTITION BY propose ORDER BY id, IF(client_payment_date IS NULL, 0, -1), client_payment_date) AS rn_payments,
        *
    FROM
        datalake_rental_guarantee_platform_raw.payment
    WHERE
        status = 'SUCCESS'
        AND (billing_type = 'CREDIT_CARD' OR billing_type = 'ANNUAL_CREDIT_CARD')
),
JDT_B AS ( -- INPUT PRODUCT
    SELECT c1.rn_end,
        ROW_NUMBER() OVER(PARTITION BY c1.rn_end ORDER BY IF(c.id_store IS NULL, 0, -1), py.rn_payments, c1.rn_end) AS rn_product,
        CAST(COALESCE(DATE_FORMAT(CAST(SPLIT(inn.createdat, 'T')[0] AS DATE),'yyyyMM'),date_format(c1.dt_sale, 'yyyyMM')) AS INT) AS Reference3, -- REQUIRED | AccrualDate
        COALESCE(CAST(SPLIT(inn.createdat, 'T')[0] AS DATE) + (interval '1' month * coalesce(c1.installment_number, 1)),c1.dt_sale + (interval '1' month * coalesce(c1.installment_number, 1))) AS DueDate,
        IF(c1.total_installments > 1,
            COALESCE(CONCAT(CAST(acquire_nsu AS INT),':',acquire_auth_code,':',c1.installment_number),CONCAT(c1.receipt,':',c1.authorization_number,':',c1.installment_number)),
            COALESCE(CONCAT(CAST(acquire_nsu AS INT), ':', acquire_auth_code),CONCAT(c1.receipt, ':', c1.authorization_number)))
        AS U_FinanceEntityEntryId, -- REQUIRED
        IF(c1.total_installments > 1,
            COALESCE(CAST(p.id AS varchar(30)),CONCAT('(!):',c1.receipt,':',c1.authorization_number,':',c1.installment_number)),
            COALESCE(CAST(p.id AS varchar(30)),CONCAT('(!):',c1.receipt,':',c1.authorization_number)))
        AS Reference, -- REQUIRED | BusinessEntityID
        COALESCE(IF(c1.total_installments > 1, CAST(py.id AS varchar(30)) || ':' || CAST(c1.installment_number AS varchar(90)), CAST(py.id AS varchar(30))),'') AS Reference2, -- REQUIRED | FinancialEntityID
        'L024' AS CostingCode, -- REQUIRED | Location
        'Q02002' AS CostingCode2, -- REQUIRED | Conting Code
        4 AS BPLID, -- REQUIRED | Branch
        '11102.01.09' AS bank_account, -- REQUIRED
        '11201.07.01' AS incoming_account, -- REQUIRED
        '41102.02.13' AS tax_account, -- REQUIRED
        '11202.03.01' AS activate_account, -- NOT_STANDARD
        COALESCE(IF(py.rn_payments = 1, p.activator_value, 0.00), 0.00) AS activate_value, -- NOT_STANDARD
        COALESCE(c.id_store, -1) AS store_id_
    FROM
        JDT_A c1
    LEFT JOIN
        datalake_wall_street_clean.charge c
        ON c.acquire_auth_code = LPAD(c1.authorization_number, 6, '0')
        AND CAST(c.acquire_nsu AS INT) = c1.receipt
    LEFT JOIN
        datalake_wall_street_raw.invoice inn
        ON c.id = inn.chargeid
    LEFT JOIN
        PAYMENTS_INSTALLMENT_VELO py
        ON CAST(py.propose AS varchar(30)) = CAST(c.id_business_entity AS varchar(30))
        AND CAST(py.due_date AS DATE) = CAST(c.ts_paid AS DATE)
        AND c1.gross_amount = py.value
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose p
        ON CAST(p.id AS BIGINT) = CAST(py.propose AS BIGINT)
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.property_propose pp
        ON p.id = pp.id_propose
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.address a
        ON pp.id_address = a.id
),
-- END | PRODUCT BLOCK

-- START | FORMAT STANDARD
JDT_C AS (
    SELECT
        ja.*,
        jb.Reference,
        jb.Reference2,
        jb.Reference3,
        CASE WEEKDAY(jb.DueDate)
            WHEN 6 THEN jb.DueDate + 2
            WHEN 7 THEN jb.DueDate + 1
            ELSE jb.DueDate
        END AS DueDate,
        jb.U_FinanceEntityEntryId,
        jb.CostingCode,
        jb.CostingCode2,
        jb.BPLID,
        jb.bank_account,
        jb.incoming_account,
        jb.tax_account,
        jb.activate_account, -- NOT_STANDARD
        jb.activate_value, -- NOT_STANDARD
        jb.store_id_,
        ROUND(ja.net_amount - ja.adjustment_sale_value,2) AS bank_value,
        ja.tax_amount AS tax_value,
        ja.adjustment_tax_value AS adj_tax_value,
        ROUND(ja.gross_amount - activate_value, 2) AS incoming_value, -- NOT_STANDARD | ja.gross_amount AS incoming_value
        ROUND(ja.adjustment_gross_value - activate_value,2) AS adj_incoming_value, -- NOT_STANDARD | ja.adjustment_sale_value AS adj_incoming_value
        ja.id_external_payment AS U_ExternalPaymentId,
        ja.description_memo AS Memo,
        'cc:'||substring(sha1(ja.TaxDate||ja.flag||ja.EC), 1, 29) AS U_RSD_UUIDSB,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_A ja
    LEFT JOIN
        JDT_B jb
        ON jb.rn_product = 1
        AND ja.rn_END = jb.rn_end
    ORDER BY
        ja.TaxDate
        ,ja.rn_end
),
JDT AS (
    SELECT -- BANK
        EC,
        MAX(store_id_) AS store_id_,
        JdtNum,
        MAX(DueDate) AS DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        MAX(Reference3) AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        bank_account AS ShortName,
        SUM(bank_value) AS Debit,
        0.00 AS Credit,
        BPLID,
        flag AS Reference1,
        EC AS Reference2_,
        MAX(Reference3) AS AdditionalReference,
        U_ExternalPaymentId AS U_FinanceEntityEntryId,
        '' AS CostingCode,
        '' AS CostingCode2,
        MAX(DueDate) AS DueDate_,
        launch_value AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    GROUP BY
        EC,
        JdtNum,
        TaxDate,
        flag,
        Memo,
        U_ExternalPaymentId,
        bank_account,
        BPLID,
        launch_value,
        U_RSD_UUIDSB,
        ts_ingested,
        year,
        month,
        day
    UNION ALL
    SELECT
        EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        tax_account AS ShortName,
        tax_value AS Debit,
        0.00 AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        CostingCode,
        CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    UNION ALL
    SELECT EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        tax_account AS ShortName,
        0.00 AS Debit,
        adj_tax_value AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        CostingCode,
        CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    UNION ALL
    SELECT
        EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        incoming_account AS ShortName,
        0.00 AS Debit,
        IF(incoming_value > 0.00, incoming_value, 0.00) AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        '' AS CostingCode,
        '' AS CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    UNION ALL
    SELECT
        EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        incoming_account AS ShortName,
        IF(adj_incoming_value > 0.00, adj_incoming_value, 0.00) AS Debit,
        0.00 AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        '' AS CostingCode,
        '' AS CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    UNION ALL
    SELECT
        EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        activate_account AS ShortName,
        0.00 AS Debit,
        IF(incoming_value > 0.00, activate_value, incoming_value + activate_value) AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        '' AS CostingCode,
        '' AS CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
    UNION ALL
    SELECT
        EC,
        store_id_,
        JdtNum,
        DueDate,
        TaxDate,
        flag AS Reference,
        EC AS Reference2,
        Reference3 AS Reference3,
        Memo,
        U_ExternalPaymentId,
        U_RSD_UUIDSB,
        JdtNum AS ParentKey,
        activate_account AS ShortName,
        IF(adj_incoming_value > 0.00, activate_value, adj_incoming_value + activate_value) AS Debit,
        0.00 AS Credit,
        BPLID,
        Reference AS Reference1,
        Reference2 AS Reference2_,
        Reference3 AS AdditionalReference,
        U_FinanceEntityEntryId,
        '' AS CostingCode,
        '' AS CostingCode2,
        DueDate AS DueDate_,
        0.00 AS original_bank_value,
        ts_ingested,
        year,
        month,
        day
    FROM
        JDT_C
),
STATUS_JDT AS (
    SELECT
        ROUND(SUM(Debit) - SUM(Credit), 2) AS `BALANCE_DIFF`,
        ROUND(MAX(original_bank_value) - SUM(IF(original_bank_value = 0.00, 0.00, Debit)),2) AS `BANK_DIFF`,
        TaxDate,
        JdtNum,
        EC,
        MAX(store_id_) AS store_id_,
        SUM(Debit) AS Debit,
        SUM(Credit) AS Credit,
        COUNT(*) AS Lines,
        'AUTO|DB' AS U_SourceClient
    FROM
        JDT
    GROUP BY
        TaxDate,
        JdtNum,
        EC
    ORDER BY
        JdtNum
)
-- END | FORMAT STANDARD

    SELECT -- OUTPUT
        sj.`BANK_DIFF` = 0.00 AND sj.`BALANCE_DIFF` = 0.00 AS `OK`,
        sj.`BANK_DIFF` = 0.00 AS `BANK_OK`,
        sj.`BANK_DIFF`,
        sj.`BALANCE_DIFF` = 0.00 AS `BALANCE_OK`,
        sj.`BALANCE_DIFF`,
        jj.EC,
        jj.store_id_ AS `STORE_ID`,
        jj.JdtNum,
        jj.DueDate,
        jj.TaxDate,
        jj.Reference,
        jj.Reference2,
        jj.Reference3,
        jj.Memo,
        jj.U_ExternalPaymentId,
        sj.U_SourceClient,
        jj.U_RSD_UUIDSB,
        jj.ParentKey,
        ROW_NUMBER() OVER(PARTITION BY jj.JdtNum ORDER BY jj.JdtNum, jj.ShortName, jj.Debit, jj.Credit) - 1 AS LineNum,
        jj.ShortName,
        jj.Debit,
        jj.Credit,
        jj.BPLID,
        jj.Reference1,
        jj.Reference2_,
        jj.AdditionalReference,
        jj.U_FinanceEntityEntryId,
        jj.CostingCode,
        jj.CostingCode2,
        jj.DueDate_,
        jj.ts_ingested,
        jj.year,
        jj.month,
        jj.day
    FROM
        JDT jj
    LEFT JOIN
        STATUS_JDT sj
        ON sj.JdtNum = jj.JdtNum
    WHERE
        (jj.Debit != 0.00 OR jj.Credit != 0.00)
    ORDER BY
        jj.JdtNum,
        jj.ShortName,
        jj.Debit,
        jj.Credit
