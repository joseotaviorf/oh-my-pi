WITH
snapshot_base AS (
    SELECT
         id_entry
        ,id_invoice
        ,sk_contract
        ,sk_invoice_reversed_entry
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,contract_status
        ,is_reversed
        ,is_write_off
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,ended_before_started
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,invoice_write_off_date
        ,real_invoice_paid_date
        ,contract_start
        ,contract_annulment
        ,year
        ,month
    FROM dw_fintech_snapshot_recon.cap_union_invoice_snapshot
    WHERE TRUE
        AND month = month(current_date())
        AND year  = year(current_date())
)
,contract_data AS (
    SELECT DISTINCT
         ab.sk_contract
        ,ab.version
        ,max(cast(cast(ab.contract_start     as timestamp) as date)) as contract_start
        ,max(cast(cast(ab.contract_annulment as timestamp) as date)) as contract_annulment
        ,ab.ended_before_started
        ,ab.contract_status
    FROM snapshot_base as ab
    GROUP BY 1,2,5,6
)
,rh_base AS (
    SELECT
         ss.sk_contract
        ,ss.type
        ,ss.description
        ,ss.status
        ,ss.due_amount
        ,ss.accrual_year_month
        ,ss.invoice_paid_date
        ,ss.id_accounting_entry
        ,ae.ts_created
        ,ae.id_payee_external
    FROM dw_fintech_snapshot_recon.robin_hood_accounting_entry_snapshot ss
    LEFT JOIN datalake_robin_hood.accounting_entry ae
        ON ae.id = ss.id_accounting_entry
    WHERE TRUE
        AND ss.month = month(current_date())
        AND ss.year  = year(current_date())
        AND ss.type IN ('CIQ Campanhas', 'Executivo For Rent')
)
,id_payee_external AS (
    SELECT
         sk_contract
        ,type AS rh_type
        ,array_join(array_sort(collect_set(id_payee_external)), ', ') AS id_payee_external
    FROM rh_base
    GROUP BY 1, 2
)
,lista_av_2024 AS (
    SELECT sk_contract FROM (VALUES
        (292340),(293897),(294238),(297484),(297615),(297732),(298297),(299273),(299660),(299796),
        (300082),(300316),(301320),(302392),(304368),(307418),(307716),(308099),(308432),(309385),
        (309665),(310409),(310787),(310989),(311208),(311318),(311896),(312306),(313096),(313879),
        (313934),(313983),(314819),(315733),(315800),(316041),(316355),(318037),(319208),(319462),
        (319521),(319855),(320730),(321073),(321450),(321571),(323270),(323753),(323890),(324559),
        (326130),(327709),(327781),(328766),(328825),(329649),(329683),(331168),(331762),(333083),
        (335907),(336218),(336849),(338229),(338343),(338501),(340644),(340964),(341392),(341660),
        (343420),(344443),(344466),(346098),(346637),(347043),(347141),(347896),(348163),(348632),
        (348699),(348855),(349517),(349798),(351109),(352188),(352463),(359346),(359848),(360023),
        (360895),(361359),(363141),(363770),(364693),(365336),(366746),(367645),(367923),(368177),
        (368180),(368593),(369385),(370390),(371700),(374059),(375949),(376864),(376906),(377564),
        (378219),(389352),(391065),(393013),(395675),(395733),(396295),(398293),(400562),(403153),
        (408699),(413136),(413790),(413832),(415952),(417079),(419029),(420059),(420961),(422972),
        (426063),(428492),(430085),(431590),(431934),(433204),(433236),(435104),(435114),(435147),
        (436569),(436911),(438783),(439068),(439385),(439639),(440347),(440971),(440980),(441672),
        (442146),(443568),(447661),(448551),(449174),(449358),(476165),(479005),(537303),(572605),
        (605732)
    ) t(sk_contract)
)
,lista_estornados_2024 AS (
    SELECT sk_contract FROM (VALUES
        (235802),(236945),(237688),(241602),(243939),(244055),(245272),(246227),(248012),(248209),
        (248333),(248440),(248958),(249611),(250161),(253030),(253192),(253367),(254074),(254921),
        (255207),(255457),(255492),(255846),(257348),(262150),(263595),(264128),(264277),(265662),
        (269233),(270559),(270600),(271385),(276888),(284109),(285728),(286790),(287639),(292157),
        (293437),(296677),(297368),(302217),(303593),(307231),(309691),(309839),(310177),(310318),
        (310808),(311244),(311534),(312466),(313676),(314588),(314708),(315092),(315826),(316014),
        (316313),(316455),(316753),(316769),(316877),(317470),(317495),(318507),(318544),(318654),
        (319177),(319472),(319664),(320590),(320839),(320990),(321264),(321442),(321833),(321985),
        (322156),(322611),(323143),(323289),(323836),(324052),(324253),(324637),(324644),(325025),
        (325036),(325500),(325683),(325726),(325900),(326045),(326580),(326586),(326999),(327044),
        (327200),(327277),(327287),(327329),(327459),(327628),(327630),(328489),(328554),(329061),
        (329321),(329589),(329931),(330179),(330308),(330410),(330753),(330905),(331235),(331250),
        (331411),(331455),(331635),(331792),(332074),(333137),(333565),(333688),(333969),(334213),
        (334415),(334476),(334554),(334899),(334900),(336133),(336242),(336882),(337115),(337119),
        (337738),(337906),(337936),(337984),(338135),(338612),(338646),(338652),(338681),(339024),
        (341036),(341275),(341730),(341893),(342034),(343156),(345533),(346154),(346626),(347161),
        (347608),(347670),(349224),(351057),(352455),(352956),(353476),(354857),(356826),(357505),
        (357813),(361139),(361618),(363125),(377997),(417850),(419299),(440931),(463711),(467148),
        (505672),(509629),(522829),(540343),(540911),(547115),(547729),(548839),(561849),(566881),
        (575318),(575609),(579592),(584245),(586405),(590400),(602002),(611158),(614470),(615535),
        (627102),(634471),(637734),(638196),(657437),(658964),(662340),(666472),(667478),(668189),
        (669487),(670554),(673332),(686591),(688083),(688871),(697203),(709769),(709851),(716296),
        (727929),(736469),(736807),(738284),(738871),(739221),(744897),(745635),(745836),(747719),
        (747976),(750643),(751090),(757536),(758968),(767801),(769619),(769864),(772141),(776885),
        (778338),(778535),(785761),(787685),(791886),(792793),(792865),(793208),(793298),(794285),
        (794566),(796022),(796753),(797097),(799116),(799306),(800053),(800854),(801524),(804916),
        (805707),(806645),(808482),(808944),(809242),(810930),(811364),(811653),(812108),(812689),
        (813080),(813488),(813847),(814082),(814898),(817058),(817721),(818983),(819516),(819740),
        (820049),(820073),(820553),(821000),(822013),(822396),(822622),(823062),(823175),(823530),
        (824607),(825266),(825864),(829741),(830304),(831414),(831740),(834276),(834543),(836932),
        (837097),(838429),(840644),(802374)
    ) t(sk_contract)
)
,f1_invoice AS (
    SELECT
         ab.id_entry
        ,ab.sk_invoice_reversed_entry
        ,ab.id_invoice
        ,ab.sk_contract
        ,ab.version
        ,ab.accounting_version
        ,ab.locale
        ,ab.localidade
        ,ab.bill_item
        ,ab.description
        ,ab.purpose
        ,ab.from_account_type
        ,ab.to_account_type
        ,ab.account_type
        ,ab.account_classification
        ,ab.status
        ,ab.paid_via
        ,ab.due_amount
        ,ab.invoice_due_amount
        ,ab.accrual_year_month
        ,ab.entry_accrual_year_month
        ,ab.entry_creation_accrual_year_month
        ,cast(cast(ab.entry_created_date     as timestamp) as date) as entry_created_date
        ,cast(cast(ab.invoice_created_date   as timestamp) as date) as invoice_created_date
        ,cast(cast(ab.invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(ab.invoice_paid_date      as timestamp) as date) as invoice_paid_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,cast(cast(ab.invoice_canceled_date  as timestamp) as date) as invoice_canceled_date
        ,cast(cast(ab.invoice_reversal_date  as timestamp) as date) as invoice_reversal_date
        ,cast(cast(ab.invoice_write_off_date as timestamp) as date) as write_off_at
        ,cast(cast(ab.contract_start         as timestamp) as date) as contract_start
        ,cast(cast(ab.contract_annulment     as timestamp) as date) as contract_annulment
        ,ab.is_write_off
        ,ab.ended_before_started
        ,ab.is_reversed
        ,ab.contract_status
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
        ,'comissao_rep_ciq'          AS fonte
        ,'CIQ Campanhas'  AS rh_type
    FROM snapshot_base ab
    WHERE TRUE
        AND (ab.bill_item IN ('brokerage adm partner postponed', 'brokerage adm partner')
             AND ab.description LIKE '%Consultor Imobiliário%')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND (ab.ended_before_started = false OR ab.ended_before_started IS NULL)
        AND (
            (ab.status NOT IN ('canceled', 'not-invoiceable')
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1)))
         OR (ab.status = 'canceled'
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
                AND cast(cast(ab.invoice_canceled_date as timestamp) as date) > last_day(add_months(current_date(), -1)))
            )
)
,f1_rh AS (
    SELECT
         CAST(NULL AS BIGINT) AS id_entry
        ,CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry
        ,CAST(NULL AS BIGINT) AS id_invoice
        ,ss.sk_contract
        ,c.version
        ,CAST(NULL AS string) AS accounting_version
        ,CAST(NULL AS string) AS locale
        ,CAST(NULL AS string) AS localidade
        ,ss.type AS bill_item
        ,ss.description
        ,'monthly'      AS purpose
        ,'quinto andar' AS from_account_type
        ,'agent'        AS to_account_type
        ,'agent'        AS account_type
        ,'payable'      AS account_classification
        ,ss.status
        ,'robinhood'    AS paid_via
        ,-1.0000 * ss.due_amount AS due_amount
        ,ss.due_amount           AS invoice_due_amount
        ,ss.accrual_year_month
        ,ss.accrual_year_month AS entry_accrual_year_month
        ,ss.accrual_year_month AS entry_creation_accrual_year_month
        ,DATE(ss.ts_created)          AS entry_created_date
        ,DATE(ss.ts_created)          AS invoice_created_date
        ,DATE(ss.invoice_paid_date)   AS invoice_due_date
        ,DATE(ss.invoice_paid_date)   AS invoice_paid_date
        ,DATE(ss.invoice_paid_date)   AS real_invoice_paid_date
        ,CAST(NULL AS date) AS invoice_canceled_date
        ,CAST(NULL AS date) AS invoice_reversal_date
        ,CAST(NULL AS date) AS write_off_at
        ,c.contract_start
        ,c.contract_annulment
        ,false AS is_write_off
        ,c.ended_before_started
        ,false AS is_reversed
        ,c.contract_status
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) > 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) < 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ss.sk_contract, (-1.0000 * ss.due_amount) ORDER BY ss.ts_created ASC, ss.id_accounting_entry ASC) AS rn_sanitization
        ,'comissao_rep_ciq'         AS fonte
        ,'CIQ Campanhas' AS rh_type
    FROM rh_base ss
    LEFT JOIN contract_data c
        ON c.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.type IN ('CIQ Campanhas')
        AND DATE(ss.invoice_paid_date) >= date'2024-01-01'
        AND ss.ts_created <= last_day(add_months(current_date(), -1))
        AND ss.status IN ('paid')
        AND c.contract_status IN ('Ativo', 'Finalizado')
        AND (c.ended_before_started = false OR c.ended_before_started IS NULL)
        AND cast(c.contract_start as date) >= date'2024-01-01'
        AND cast(c.contract_start as date) <= last_day(add_months(current_date(), -1))
)
,f2_invoice AS (
    SELECT
         ab.id_entry
        ,ab.sk_invoice_reversed_entry
        ,ab.id_invoice
        ,ab.sk_contract
        ,ab.version
        ,ab.accounting_version
        ,ab.locale
        ,ab.localidade
        ,ab.bill_item
        ,ab.description
        ,ab.purpose
        ,ab.from_account_type
        ,ab.to_account_type
        ,ab.account_type
        ,ab.account_classification
        ,ab.status
        ,ab.paid_via
        ,ab.due_amount
        ,ab.invoice_due_amount
        ,ab.accrual_year_month
        ,ab.entry_accrual_year_month
        ,ab.entry_creation_accrual_year_month
        ,cast(cast(ab.entry_created_date     as timestamp) as date) as entry_created_date
        ,cast(cast(ab.invoice_created_date   as timestamp) as date) as invoice_created_date
        ,cast(cast(ab.invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(ab.invoice_paid_date      as timestamp) as date) as invoice_paid_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,cast(cast(ab.invoice_canceled_date  as timestamp) as date) as invoice_canceled_date
        ,cast(cast(ab.invoice_reversal_date  as timestamp) as date) as invoice_reversal_date
        ,cast(cast(ab.invoice_write_off_date as timestamp) as date) as write_off_at
        ,cast(cast(ab.contract_start         as timestamp) as date) as contract_start
        ,cast(cast(ab.contract_annulment     as timestamp) as date) as contract_annulment
        ,ab.is_write_off
        ,ab.ended_before_started
        ,ab.is_reversed
        ,ab.contract_status
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
        ,'comissao_rep_select'           AS fonte
        ,'Executivo For Rent' AS rh_type
    FROM snapshot_base ab
    WHERE TRUE
        AND ab.bill_item IN ('brokerage partner select', 'brokerage partner select postponed')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND (ab.ended_before_started = false OR ab.ended_before_started IS NULL)
        AND (
            (ab.status NOT IN ('canceled', 'not-invoiceable')
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1)))
         OR (ab.status = 'canceled'
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
                AND cast(cast(ab.invoice_canceled_date as timestamp) as date) > last_day(add_months(current_date(), -1)))
            )
)
,f2_rh AS (
    SELECT
         CAST(NULL AS BIGINT) AS id_entry
        ,CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry
        ,CAST(NULL AS BIGINT) AS id_invoice
        ,ss.sk_contract
        ,c.version
        ,CAST(NULL AS string) AS accounting_version
        ,CAST(NULL AS string) AS locale
        ,CAST(NULL AS string) AS localidade
        ,ss.type AS bill_item
        ,ss.description
        ,'monthly'      AS purpose
        ,'quinto andar' AS from_account_type
        ,'agent'        AS to_account_type
        ,'agent'        AS account_type
        ,'payable'      AS account_classification
        ,ss.status
        ,'robinhood'    AS paid_via
        ,-1.0000 * ss.due_amount AS due_amount
        ,ss.due_amount           AS invoice_due_amount
        ,ss.accrual_year_month
        ,ss.accrual_year_month AS entry_accrual_year_month
        ,ss.accrual_year_month AS entry_creation_accrual_year_month
        ,DATE(ss.ts_created)        AS entry_created_date
        ,DATE(ss.ts_created)        AS invoice_created_date
        ,DATE(ss.invoice_paid_date) AS invoice_due_date
        ,DATE(ss.invoice_paid_date) AS invoice_paid_date
        ,DATE(ss.invoice_paid_date) AS real_invoice_paid_date
        ,CAST(NULL AS date) AS invoice_canceled_date
        ,CAST(NULL AS date) AS invoice_reversal_date
        ,CAST(NULL AS date) AS write_off_at
        ,c.contract_start
        ,c.contract_annulment
        ,false AS is_write_off
        ,c.ended_before_started
        ,false AS is_reversed
        ,c.contract_status
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) > 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ss.accrual_year_month, ABS(ss.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) < 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ss.accrual_year_month, ABS(ss.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ss.sk_contract, ss.accrual_year_month, (-1.0000 * ss.due_amount) ORDER BY ss.ts_created ASC, ss.id_accounting_entry ASC) AS rn_sanitization
        ,'comissao_rep_select'           AS fonte
        ,'Executivo For Rent' AS rh_type
    FROM rh_base ss
    LEFT JOIN contract_data c
        ON c.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.type IN ('Executivo For Rent')
        AND DATE(ss.invoice_paid_date) >= date'2024-01-01'
        AND ss.ts_created <= last_day(add_months(current_date(), -1))
        AND ss.status IN ('paid')
        AND c.contract_status IN ('Ativo', 'Finalizado')
        AND (c.ended_before_started = false OR c.ended_before_started IS NULL)
        AND cast(c.contract_start as date) >= date'2024-01-01'
        AND cast(c.contract_start as date) <= last_day(add_months(current_date(), -1))
)
,av_invoices AS (
    SELECT
         ab.id_invoice
        ,ab.id_entry
        ,ab.sk_contract
        ,ab.account_type
        ,ab.status
        ,ab.invoice_due_amount
        ,ab.description
        ,ab.bill_item
        ,ab.due_amount
        ,ab.entry_created_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.account_type, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.account_type, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.account_type, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
    FROM snapshot_base AS ab
    WHERE TRUE
        AND ab.bill_item IN ('early termination fee non protection', 'early termination fee')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND ab.ended_before_started = TRUE
        AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
        AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
        AND ((ab.status IN ('paid', 'divergent payment', 'written down')
                AND cast(cast(ab.real_invoice_paid_date as timestamp) as date) <= last_day(add_months(current_date(), -1)))
          OR (ab.status IN ('not payable')
                AND cast(cast(ab.invoice_due_date as timestamp) as date) <= last_day(add_months(current_date(), -1)))
            )
)
,av_invoices_all AS (
    SELECT
         id_invoice
        ,id_entry
        ,sk_contract
        ,account_type
        ,status
        ,invoice_due_amount
        ,description
        ,bill_item
        ,due_amount
        ,entry_created_date
        ,real_invoice_paid_date
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,CASE WHEN due_amount > 0 AND rn_sanitization <= negative_entries_count THEN TRUE
              WHEN due_amount < 0 AND rn_sanitization <= positive_entries_count THEN TRUE
              ELSE FALSE
         END AS opposite_entries
    FROM av_invoices
)
,negotiation_all AS (
    SELECT
         fd.id_contract
        ,CAST(fd.id_invoice AS BIGINT)       AS original_invoice_id
        ,CAST(fni.id_invoice_extra AS BIGINT) AS daughter_invoice_id
        ,fd.due_amount
        ,fni.net_amount AS main_amount_net
        ,CASE WHEN fni.installment_status IN ('paid','failed') THEN fni.net_amount ELSE 0 END AS paid_amount_net
        ,fni.installment_status
    FROM dw_collection_recovery_quintoandar.fact_debt AS fd
    LEFT JOIN dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS bm
        ON fd.sk_debt = bm.sk_debt
    LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni
        ON fni.sk_negotiation = bm.sk_negotiation
    WHERE fni.installment_status NOT IN ('ignored', 'canceled-by-chargeback', 'canceled')
)
,negotiation_expired AS (
    SELECT
         id_contract
        ,original_invoice_id
        ,daughter_invoice_id
        ,installment_status
        ,main_amount_net
        ,paid_amount_net
    FROM negotiation_all
    WHERE installment_status = 'expired'
)
,negotiation_grandkid_all AS (
    SELECT
         ne.id_contract
        ,ne.daughter_invoice_id AS new_mother_invoice_id
        ,na.daughter_invoice_id AS grandkid_invoice_id
        ,na.installment_status  AS grandkid_installment_status
        ,na.main_amount_net     AS grandkid_total_main_amount
        ,na.paid_amount_net     AS grandkid_total_paid_amount
        ,CASE WHEN na.installment_status NOT IN ('paid','failed') THEN false ELSE true END AS grandkid_check_paid
    FROM negotiation_expired ne
    LEFT JOIN negotiation_all na
        ON ne.daughter_invoice_id = na.original_invoice_id
)
,negotiation_grandkid AS (
    SELECT
         id_contract
        ,new_mother_invoice_id
        ,MIN(grandkid_check_paid) AS grandkids_fully_paid
    FROM negotiation_grandkid_all
    GROUP BY 1, 2
)
,negotiation_granny_all AS (
    SELECT
         na.id_contract
        ,na.original_invoice_id AS granny_invoice_id
        ,na.daughter_invoice_id
        ,na.installment_status  AS granny_installment_status
        ,na.main_amount_net     AS granny_total_main_amount
        ,na.paid_amount_net     AS granny_total_paid_amount
        ,CASE
            WHEN na.installment_status NOT IN ('paid','failed','expired') THEN false
            WHEN na.installment_status = 'expired' THEN gk.grandkids_fully_paid
            ELSE true
         END AS kids_check_paid
        ,gk.new_mother_invoice_id
        ,gk.grandkids_fully_paid
    FROM negotiation_all na
    LEFT JOIN negotiation_grandkid gk
        ON na.daughter_invoice_id = gk.new_mother_invoice_id
)
,negotiation_granny AS (
    SELECT
         id_contract
        ,granny_invoice_id
        ,MIN(kids_check_paid) AS kids_fully_paid
    FROM negotiation_granny_all
    GROUP BY 1, 2
)
,invoices_paid_and_negotiated AS (
    SELECT
         av.id_invoice
        ,av.sk_contract
        ,av.account_type
        ,av.status
        ,av.invoice_due_amount
        ,COALESCE(TRY_CAST(REGEXP_EXTRACT(av.description, '[0-9]+ de ([0-9]+)', 1) AS INTEGER), 1) AS total_installments
        ,COALESCE(TRY_CAST(REGEXP_EXTRACT(av.description, '([0-9]+) de [0-9]+', 1) AS INTEGER), 1) AS current_installment
        ,SUM(av.due_amount) AS total_invoice_amount
        ,SUM(av.due_amount * COALESCE(TRY_CAST(REGEXP_EXTRACT(av.description, '[0-9]+ de ([0-9]+)', 1) AS INTEGER), 1)) AS total_amount
        ,n.kids_fully_paid
    FROM av_invoices_all AS av
    LEFT JOIN negotiation_granny AS n
        ON av.id_invoice = CAST(n.granny_invoice_id AS BIGINT)
        AND av.status = 'written down'
    WHERE TRUE
        AND av.opposite_entries = FALSE
        AND ((av.status = 'not payable')
          OR (av.status IN ('paid','written down','divergent payment')
                AND date(av.real_invoice_paid_date) <= last_day(add_months(current_date(), -1))))
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 10
    HAVING SUM(av.due_amount * COALESCE(TRY_CAST(REGEXP_EXTRACT(av.description, '[0-9]+ de ([0-9]+)', 1) AS INTEGER), 1)) >= 0
)
,calculo_invoices_paids AS (
    SELECT
         id_invoice
        ,sk_contract
        ,account_type
        ,status
        ,invoice_due_amount
        ,total_installments
        ,current_installment
        ,total_invoice_amount
        ,total_amount
        ,kids_fully_paid
        ,SUM(CASE WHEN status <> 'written down' THEN total_invoice_amount ELSE 0 END) OVER (PARTITION BY sk_contract, account_type) AS total_paid_amount_not_wd
        ,ROW_NUMBER() OVER (PARTITION BY sk_contract, account_type ORDER BY id_invoice DESC) AS rn
    FROM invoices_paid_and_negotiated
)
,filtro_wd AS (
    SELECT
         id_invoice
        ,sk_contract
        ,account_type
        ,status
        ,invoice_due_amount
        ,total_installments
        ,current_installment
        ,total_invoice_amount
        ,total_amount
        ,kids_fully_paid
        ,total_paid_amount_not_wd
        ,rn
    FROM calculo_invoices_paids
    WHERE TRUE
        AND ((status <> 'written down')
          OR (status = 'written down' AND kids_fully_paid = true))
)
,filtro_multa_paga AS (
    SELECT
         sk_contract
        ,account_type
        ,round(total_amount)        AS expected_total_amount
        ,sum(total_invoice_amount)  AS paid_total_amount
    FROM filtro_wd
    GROUP BY 1,2,3
    HAVING sum(total_invoice_amount) > 0
)
,pos_sem_multa AS (
    SELECT DISTINCT
         sk_contract
        ,id_invoice
        ,account_type
        ,status
        ,bill_item
        ,purpose
        ,invoice_due_amount
        ,cast(cast(invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,CASE WHEN bill_item = 'early termination fee' THEN 1 ELSE 0 END AS has_early_termination_fee_flag
    FROM snapshot_base
    WHERE TRUE
        AND cast(cast(contract_start as timestamp) as date) >= date'2024-01-01'
        AND cast(cast(contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
        AND bill_item IN ('brokerage adm partner postponed','early termination fee non protection', 'early termination fee')
        AND purpose = 'pos rental'
        AND account_type = 'landlord'
)
,flag_pos_sem_multa AS (
    SELECT
         sk_contract
        ,id_invoice
        ,account_type
        ,status
        ,bill_item
        ,purpose
        ,invoice_due_amount
        ,invoice_due_date
        ,real_invoice_paid_date
        ,has_early_termination_fee_flag
        ,CASE WHEN max(has_early_termination_fee_flag) OVER (PARTITION BY sk_contract) = 1 THEN TRUE ELSE FALSE END AS contract_has_early_termination_fee
    FROM pos_sem_multa
)
,filtro_corretagem_zerada AS (
    SELECT DISTINCT
         sk_contract
        ,account_type
        ,0 AS expected_total_amount
        ,0 AS paid_total_amount
    FROM flag_pos_sem_multa
    WHERE TRUE
        AND bill_item IN ('brokerage adm partner postponed')
        AND purpose = 'pos rental'
        AND invoice_due_amount = 0
        AND account_type = 'landlord'
        AND DATE(invoice_due_date) <= last_day(add_months(current_date(), -1))
        AND contract_has_early_termination_fee = FALSE
)
,corretagem_sem_multa AS (
    SELECT DISTINCT
         sk_contract
        ,id_invoice
        ,account_type
        ,0 AS expected_total_amount
        ,0 AS paid_total_amount
        ,status
        ,cast(cast(real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,invoice_due_amount
    FROM flag_pos_sem_multa
    WHERE TRUE
        AND bill_item IN ('brokerage adm partner postponed')
        AND purpose = 'pos rental'
        AND invoice_due_amount > 0
        AND account_type = 'landlord'
        AND contract_has_early_termination_fee = FALSE
        AND (status IN ('paid', 'divergent payment', 'writen down')
             AND date(real_invoice_paid_date) <= last_day(add_months(current_date(), -1)))
)
,corretagem_sem_multa_com_neg AS (
    SELECT
         av.sk_contract
        ,av.id_invoice
        ,av.account_type
        ,av.expected_total_amount
        ,av.paid_total_amount
        ,av.status
        ,av.real_invoice_paid_date
        ,av.invoice_due_amount
        ,n.kids_fully_paid
    FROM corretagem_sem_multa av
    LEFT JOIN negotiation_granny AS n
        ON av.id_invoice = CAST(n.granny_invoice_id AS BIGINT)
        AND av.status = 'written down'
    WHERE TRUE
        AND ((av.status <> 'written down')
          OR (av.status = 'written down' AND n.kids_fully_paid = true))
)
,filtro_corretagem_sem_multa AS (
    SELECT
         sk_contract
        ,account_type
        ,expected_total_amount
        ,paid_total_amount
    FROM corretagem_sem_multa_com_neg
)
,union_ctes AS (
    SELECT DISTINCT sk_contract
    FROM filtro_multa_paga
    WHERE round(expected_total_amount) = round(paid_total_amount)
    UNION
    SELECT DISTINCT sk_contract FROM filtro_corretagem_zerada
    UNION
    SELECT DISTINCT sk_contract FROM filtro_corretagem_sem_multa
)
,f3_invoice AS (
    SELECT
         ab.id_entry
        ,ab.sk_invoice_reversed_entry
        ,ab.id_invoice
        ,c.sk_contract
        ,ab.version
        ,ab.accounting_version
        ,ab.locale
        ,ab.localidade
        ,ab.bill_item
        ,ab.description
        ,ab.purpose
        ,ab.from_account_type
        ,ab.to_account_type
        ,ab.account_type
        ,ab.account_classification
        ,ab.status
        ,ab.paid_via
        ,ab.due_amount
        ,ab.invoice_due_amount
        ,ab.accrual_year_month
        ,ab.entry_accrual_year_month
        ,ab.entry_creation_accrual_year_month
        ,cast(cast(ab.entry_created_date     as timestamp) as date) as entry_created_date
        ,cast(cast(ab.invoice_created_date   as timestamp) as date) as invoice_created_date
        ,cast(cast(ab.invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(ab.invoice_paid_date      as timestamp) as date) as invoice_paid_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,cast(cast(ab.invoice_canceled_date  as timestamp) as date) as invoice_canceled_date
        ,cast(cast(ab.invoice_reversal_date  as timestamp) as date) as invoice_reversal_date
        ,cast(cast(ab.invoice_write_off_date as timestamp) as date) as write_off_at
        ,cast(cast(ab.contract_start         as timestamp) as date) as contract_start
        ,cast(cast(ab.contract_annulment     as timestamp) as date) as contract_annulment
        ,ab.is_write_off
        ,ab.ended_before_started
        ,ab.is_reversed
        ,ab.contract_status
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
        ,'comissao_rep_ciq_av' AS fonte
        ,'CIQ Campanhas' AS rh_type
    FROM union_ctes AS c
    LEFT JOIN snapshot_base AS ab
        ON c.sk_contract = ab.sk_contract
    WHERE TRUE
        AND (ab.bill_item IN ('brokerage adm partner postponed', 'brokerage adm partner')
             AND ab.description LIKE '%Consultor Imobiliário%')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND ab.ended_before_started = TRUE
        AND ((ab.status NOT IN ('canceled', 'not-invoiceable')
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1)))
          OR (ab.status IN ('canceled')
                AND cast(cast(ab.contract_start as timestamp) as date) >= date'2024-01-01'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
                AND cast(cast(ab.invoice_canceled_date as timestamp) as date) > last_day(add_months(current_date(), -1)))
            )
)
,f3_rh AS (
    SELECT
         CAST(NULL AS BIGINT) AS id_entry
        ,CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry
        ,CAST(NULL AS BIGINT) AS id_invoice
        ,ss.sk_contract
        ,c.version
        ,CAST(NULL AS string) AS accounting_version
        ,CAST(NULL AS string) AS locale
        ,CAST(NULL AS string) AS localidade
        ,ss.type AS bill_item
        ,ss.description
        ,'monthly'      AS purpose
        ,'quinto andar' AS from_account_type
        ,'agent'        AS to_account_type
        ,'agent'        AS account_type
        ,'payable'      AS account_classification
        ,ss.status
        ,'robinhood'    AS paid_via
        ,-1.0000 * ss.due_amount AS due_amount
        ,ss.due_amount           AS invoice_due_amount
        ,ss.accrual_year_month
        ,ss.accrual_year_month AS entry_accrual_year_month
        ,ss.accrual_year_month AS entry_creation_accrual_year_month
        ,DATE(ss.ts_created)        AS entry_created_date
        ,DATE(ss.ts_created)        AS invoice_created_date
        ,DATE(ss.invoice_paid_date) AS invoice_due_date
        ,DATE(ss.invoice_paid_date) AS invoice_paid_date
        ,DATE(ss.invoice_paid_date) AS real_invoice_paid_date
        ,CAST(NULL AS date) AS invoice_canceled_date
        ,CAST(NULL AS date) AS invoice_reversal_date
        ,CAST(NULL AS date) AS write_off_at
        ,c.contract_start
        ,c.contract_annulment
        ,false AS is_write_off
        ,c.ended_before_started
        ,false AS is_reversed
        ,c.contract_status
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) > 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) < 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ss.sk_contract, (-1.0000 * ss.due_amount) ORDER BY ss.ts_created ASC, ss.id_accounting_entry ASC) AS rn_sanitization
        ,'comissao_rep_ciq_av' AS fonte
        ,'CIQ Campanhas' AS rh_type
    FROM rh_base ss
    LEFT JOIN contract_data c
        ON c.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.type IN ('CIQ Campanhas')
        AND ss.ts_created >= date'2024-01-01'
        AND ss.ts_created <= last_day(add_months(current_date(), -1))
        AND ss.status IN ('paid')
        AND c.contract_status IN ('Ativo', 'Finalizado')
        AND c.ended_before_started = true
        AND cast(c.contract_start as date) >= date'2024-01-01'
        AND cast(c.contract_start as date) <= last_day(add_months(current_date(), -1))
        AND ss.sk_contract IN (SELECT sk_contract FROM union_ctes)
)
,f4_invoice AS (
    SELECT
         ab.id_entry
        ,ab.sk_invoice_reversed_entry
        ,ab.id_invoice
        ,ab.sk_contract
        ,ab.version
        ,ab.accounting_version
        ,ab.locale
        ,ab.localidade
        ,ab.bill_item
        ,ab.description
        ,ab.purpose
        ,ab.from_account_type
        ,ab.to_account_type
        ,ab.account_type
        ,ab.account_classification
        ,ab.status
        ,ab.paid_via
        ,ab.due_amount
        ,ab.invoice_due_amount
        ,ab.accrual_year_month
        ,ab.entry_accrual_year_month
        ,ab.entry_creation_accrual_year_month
        ,cast(cast(ab.entry_created_date     as timestamp) as date) as entry_created_date
        ,cast(cast(ab.invoice_created_date   as timestamp) as date) as invoice_created_date
        ,cast(cast(ab.invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(ab.invoice_paid_date      as timestamp) as date) as invoice_paid_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,cast(cast(ab.invoice_canceled_date  as timestamp) as date) as invoice_canceled_date
        ,cast(cast(ab.invoice_reversal_date  as timestamp) as date) as invoice_reversal_date
        ,cast(cast(ab.invoice_write_off_date as timestamp) as date) as write_off_at
        ,cast(cast(ab.contract_start         as timestamp) as date) as contract_start
        ,cast(cast(ab.contract_annulment     as timestamp) as date) as contract_annulment
        ,ab.is_write_off
        ,ab.ended_before_started
        ,ab.is_reversed
        ,ab.contract_status
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
        ,'corretor_ciq_av_2024' AS fonte
        ,'CIQ Campanhas' AS rh_type
    FROM snapshot_base ab
    WHERE TRUE
        AND (ab.bill_item IN ('brokerage adm partner postponed', 'brokerage adm partner')
             AND ab.description LIKE '%Consultor Imobiliário%')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND ((ab.status NOT IN ('canceled', 'not-invoiceable')
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1)))
          OR (ab.status = 'canceled'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
                AND cast(cast(ab.invoice_canceled_date as timestamp) as date) > last_day(add_months(current_date(), -1)))
            )
        AND ab.sk_contract IN (SELECT sk_contract FROM lista_av_2024)
)
,f4_rh AS (
    SELECT
         CAST(NULL AS BIGINT) AS id_entry
        ,CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry
        ,CAST(NULL AS BIGINT) AS id_invoice
        ,ss.sk_contract
        ,c.version
        ,CAST(NULL AS string) AS accounting_version
        ,CAST(NULL AS string) AS locale
        ,CAST(NULL AS string) AS localidade
        ,ss.type AS bill_item
        ,ss.description
        ,'monthly'      AS purpose
        ,'quinto andar' AS from_account_type
        ,'agent'        AS to_account_type
        ,'agent'        AS account_type
        ,'payable'      AS account_classification
        ,ss.status
        ,'robinhood'    AS paid_via
        ,-1.0000 * ss.due_amount AS due_amount
        ,ss.due_amount           AS invoice_due_amount
        ,ss.accrual_year_month
        ,ss.accrual_year_month AS entry_accrual_year_month
        ,ss.accrual_year_month AS entry_creation_accrual_year_month
        ,DATE(ss.ts_created)        AS entry_created_date
        ,DATE(ss.ts_created)        AS invoice_created_date
        ,DATE(ss.invoice_paid_date) AS invoice_due_date
        ,DATE(ss.invoice_paid_date) AS invoice_paid_date
        ,DATE(ss.invoice_paid_date) AS real_invoice_paid_date
        ,CAST(NULL AS date) AS invoice_canceled_date
        ,CAST(NULL AS date) AS invoice_reversal_date
        ,CAST(NULL AS date) AS write_off_at
        ,c.contract_start
        ,c.contract_annulment
        ,false AS is_write_off
        ,c.ended_before_started
        ,false AS is_reversed
        ,c.contract_status
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) > 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN (-1.0000 * ss.due_amount) < 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ss.sk_contract, (-1.0000 * ss.due_amount) ORDER BY ss.ts_created ASC, ss.id_accounting_entry ASC) AS rn_sanitization
        ,'corretor_ciq_av_2024' AS fonte
        ,'CIQ Campanhas' AS rh_type
    FROM rh_base ss
    LEFT JOIN contract_data c
        ON c.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.type IN ('CIQ Campanhas')
        AND ss.ts_created <= last_day(add_months(current_date(), -1))
        AND DATE(ss.invoice_paid_date) >= date'2025-01-01'
        AND ss.status IN ('paid')
        AND c.contract_status IN ('Ativo', 'Finalizado')
        AND cast(c.contract_start as date) <= last_day(add_months(current_date(), -1))
        AND ss.sk_contract IN (SELECT sk_contract FROM lista_av_2024)
)
,f5_invoice AS (
    SELECT
         ab.id_entry
        ,ab.sk_invoice_reversed_entry
        ,ab.id_invoice
        ,ab.sk_contract
        ,ab.version
        ,ab.accounting_version
        ,ab.locale
        ,ab.localidade
        ,ab.bill_item
        ,ab.description
        ,ab.purpose
        ,ab.from_account_type
        ,ab.to_account_type
        ,ab.account_type
        ,ab.account_classification
        ,ab.status
        ,ab.paid_via
        ,ab.due_amount
        ,ab.invoice_due_amount
        ,ab.accrual_year_month
        ,ab.entry_accrual_year_month
        ,ab.entry_creation_accrual_year_month
        ,cast(cast(ab.entry_created_date     as timestamp) as date) as entry_created_date
        ,cast(cast(ab.invoice_created_date   as timestamp) as date) as invoice_created_date
        ,cast(cast(ab.invoice_due_date       as timestamp) as date) as invoice_due_date
        ,cast(cast(ab.invoice_paid_date      as timestamp) as date) as invoice_paid_date
        ,cast(cast(ab.real_invoice_paid_date as timestamp) as date) as real_invoice_paid_date
        ,cast(cast(ab.invoice_canceled_date  as timestamp) as date) as invoice_canceled_date
        ,cast(cast(ab.invoice_reversal_date  as timestamp) as date) as invoice_reversal_date
        ,cast(cast(ab.invoice_write_off_date as timestamp) as date) as write_off_at
        ,cast(cast(ab.contract_start         as timestamp) as date) as contract_start
        ,cast(cast(ab.contract_annulment     as timestamp) as date) as contract_annulment
        ,ab.is_write_off
        ,ab.ended_before_started
        ,ab.is_reversed
        ,ab.contract_status
        ,COUNT(CASE WHEN ab.due_amount > 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ab.due_amount < 0 THEN 1 END) OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ABS(ab.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ab.sk_contract, ab.id_invoice, ab.bill_item, ab.due_amount ORDER BY ab.entry_created_date ASC, ab.id_entry ASC) AS rn_sanitization
        ,'corretor_ciq_estornos' AS fonte
        ,'CIQ Campanhas'         AS rh_type
    FROM snapshot_base ab
    WHERE TRUE
        AND (ab.bill_item IN ('brokerage adm partner postponed', 'brokerage adm partner')
             AND ab.description LIKE '%Consultor Imobiliário%')
        AND ab.contract_status IN ('Ativo', 'Finalizado')
        AND ((ab.status NOT IN ('canceled', 'not-invoiceable')
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1)))
          OR (ab.status = 'canceled'
                AND cast(cast(ab.contract_start as timestamp) as date) <= last_day(add_months(current_date(), -1))
                AND cast(cast(ab.invoice_canceled_date as timestamp) as date) > last_day(add_months(current_date(), -1)))
            )
        AND ab.sk_contract IN (SELECT sk_contract FROM lista_estornados_2024)
)
,f5_rh AS (
    SELECT
         CAST(NULL AS BIGINT) AS id_entry
        ,CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry
        ,CAST(NULL AS BIGINT) AS id_invoice
        ,ss.sk_contract
        ,c.version
        ,CAST(NULL AS string) AS accounting_version
        ,CAST(NULL AS string) AS locale
        ,CAST(NULL AS string) AS localidade
        ,ss.type AS bill_item
        ,ss.description
        ,'monthly'      AS purpose
        ,'quinto andar' AS from_account_type
        ,'agent'        AS to_account_type
        ,'agent'        AS account_type
        ,'payable'      AS account_classification
        ,ss.status
        ,'robinhood'    AS paid_via
        ,-1.0000 * ss.due_amount AS due_amount
        ,ss.due_amount           AS invoice_due_amount
        ,ss.accrual_year_month
        ,ss.accrual_year_month AS entry_accrual_year_month
        ,ss.accrual_year_month AS entry_creation_accrual_year_month
        ,DATE(ss.ts_created)        AS entry_created_date
        ,DATE(ss.ts_created)        AS invoice_created_date
        ,DATE(ss.invoice_paid_date) AS invoice_due_date
        ,DATE(ss.invoice_paid_date) AS invoice_paid_date
        ,DATE(ss.invoice_paid_date) AS real_invoice_paid_date
        ,CAST(NULL AS date) AS invoice_canceled_date
        ,CAST(NULL AS date) AS invoice_reversal_date
        ,CAST(NULL AS date) AS write_off_at
        ,c.contract_start
        ,c.contract_annulment
        ,false AS is_write_off
        ,c.ended_before_started
        ,false AS is_reversed
        ,c.contract_status
        ,COUNT(CASE WHEN ss.due_amount > 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS positive_entries_count
        ,COUNT(CASE WHEN ss.due_amount < 0 THEN 1 END) OVER (PARTITION BY ss.sk_contract, ABS(ss.due_amount)) AS negative_entries_count
        ,ROW_NUMBER() OVER (PARTITION BY ss.sk_contract, ss.due_amount ORDER BY ss.ts_created ASC, ss.id_accounting_entry ASC) AS rn_sanitization
        ,'corretor_ciq_estornos' AS fonte
        ,'CIQ Campanhas'         AS rh_type
    FROM rh_base ss
    LEFT JOIN contract_data c
        ON c.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.type IN ('CIQ Campanhas')
        AND DATE(ss.invoice_paid_date) <= last_day(add_months(current_date(), -1))
        AND ss.status IN ('paid')
        AND c.contract_status IN ('Ativo', 'Finalizado')
        AND cast(c.contract_start as date) <= last_day(add_months(current_date(), -1))
        AND ss.sk_contract IN (SELECT sk_contract FROM lista_estornados_2024)
)
,base_union AS (
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f1_invoice
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f1_rh
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f2_invoice
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f2_rh
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f3_invoice
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f3_rh
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f4_invoice
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f4_rh
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f5_invoice
    UNION ALL
    SELECT
         id_entry
        ,sk_invoice_reversed_entry
        ,id_invoice
        ,sk_contract
        ,version
        ,accounting_version
        ,locale
        ,localidade
        ,bill_item
        ,description
        ,purpose
        ,from_account_type
        ,to_account_type
        ,account_type
        ,account_classification
        ,status
        ,paid_via
        ,due_amount
        ,invoice_due_amount
        ,accrual_year_month
        ,entry_accrual_year_month
        ,entry_creation_accrual_year_month
        ,entry_created_date
        ,invoice_created_date
        ,invoice_due_date
        ,invoice_paid_date
        ,real_invoice_paid_date
        ,invoice_canceled_date
        ,invoice_reversal_date
        ,write_off_at
        ,contract_start
        ,contract_annulment
        ,is_write_off
        ,ended_before_started
        ,is_reversed
        ,contract_status
        ,positive_entries_count
        ,negative_entries_count
        ,rn_sanitization
        ,fonte
        ,rh_type
    FROM f5_rh
)
,account_balance AS (
    SELECT
         iv.id_entry
        ,iv.sk_invoice_reversed_entry
        ,iv.id_invoice
        ,iv.sk_contract
        ,iv.version
        ,iv.accounting_version
        ,iv.locale
        ,iv.localidade
        ,iv.bill_item
        ,iv.description
        ,iv.purpose
        ,iv.from_account_type
        ,iv.to_account_type
        ,iv.account_type
        ,iv.account_classification
        ,iv.status
        ,iv.paid_via
        ,-1.00000 * iv.due_amount AS due_amount
        ,iv.invoice_due_amount
        ,iv.accrual_year_month
        ,iv.entry_accrual_year_month
        ,DATE(iv.entry_created_date)     AS entry_created_date
        ,DATE(iv.invoice_created_date)   AS invoice_created_date
        ,DATE(iv.invoice_due_date)       AS invoice_due_date
        ,DATE(iv.real_invoice_paid_date) AS real_invoice_paid_date
        ,DATE(iv.invoice_paid_date)      AS invoice_paid_date
        ,DATE(iv.invoice_canceled_date)  AS invoice_canceled_date
        ,iv.is_write_off
        ,DATE(iv.write_off_at)           AS write_off_at
        ,DATE(iv.contract_start)         AS contract_start
        ,DATE(iv.contract_annulment)     AS contract_annulment
        ,iv.ended_before_started
        ,iv.contract_status
        ,CASE
            WHEN iv.due_amount > 0 AND iv.rn_sanitization <= iv.negative_entries_count THEN TRUE
            WHEN iv.due_amount < 0 AND iv.rn_sanitization <= iv.positive_entries_count THEN TRUE
            ELSE FALSE
         END AS opposite_entries
        ,id_p.id_payee_external
        ,CASE WHEN iv.rh_type = 'Executivo For Rent' THEN ag.select_brokerage_amount
              ELSE ag.ciq_brokerage_amount
         END AS brokerage_amount
        ,sum(CASE WHEN iv.bill_item =  iv.rh_type THEN iv.due_amount ELSE 0 END) OVER (PARTITION BY iv.fonte, iv.sk_contract) AS rh_balance
        ,sum(CASE WHEN iv.bill_item <> iv.rh_type THEN iv.due_amount ELSE 0 END) OVER (PARTITION BY iv.fonte, iv.sk_contract) AS invoice_balance
        ,sum(iv.due_amount) OVER (PARTITION BY iv.fonte, iv.sk_contract) AS contract_balance
        ,iv.fonte
    FROM base_union iv
    LEFT JOIN datalake_accounting_funnel.for_rent_contract_brokerage ag
        ON ag.id_contract = iv.sk_contract
    LEFT JOIN id_payee_external id_p
        ON id_p.sk_contract = iv.sk_contract
        AND id_p.rh_type    = iv.rh_type
)
SELECT
     id_entry
    ,sk_invoice_reversed_entry
    ,id_invoice
    ,sk_contract
    ,version
    ,accounting_version
    ,locale
    ,localidade
    ,bill_item
    ,description
    ,purpose
    ,from_account_type
    ,to_account_type
    ,account_type
    ,account_classification
    ,status
    ,paid_via
    ,due_amount
    ,invoice_due_amount
    ,accrual_year_month
    ,entry_accrual_year_month
    ,entry_created_date
    ,invoice_created_date
    ,invoice_due_date
    ,real_invoice_paid_date
    ,invoice_paid_date
    ,invoice_canceled_date
    ,is_write_off
    ,write_off_at
    ,contract_start
    ,contract_annulment
    ,ended_before_started
    ,contract_status
    ,opposite_entries
    ,id_payee_external
    ,brokerage_amount
    ,rh_balance
    ,invoice_balance
    ,contract_balance
    ,fonte
    ,'211408' AS conta_numero
    ,'Comissão Corretor a Repassar' AS conta_nome
    ,last_day(add_months(current_date(), -1)) AS data_fim
    ,current_timestamp() AS gerado_em
    ,date_format(current_date(), 'yyyyMM') AS snapshot
    ,TRUE AS entra_no_saldo
FROM account_balance
WHERE TRUE
    AND CASE
            WHEN fonte = 'comissao_rep_ciq'                 THEN abs(contract_balance) > 0.99
            WHEN fonte = 'comissao_rep_select'              THEN abs(contract_balance) > 0.99
            WHEN fonte = 'comissao_rep_ciq_av'         THEN opposite_entries = FALSE
            WHEN fonte = 'corretor_ciq_av_2024'         THEN opposite_entries = FALSE
            WHEN fonte = 'corretor_ciq_estornos' THEN TRUE
            ELSE TRUE
        END
    AND NOT (fonte IN ('comissao_rep_ciq', 'comissao_rep_ciq_av') AND sk_contract IN (
        657437,658964,662340,666472,667478,668189,669487,670554,673332,686591,
        688083,688871,697203,709769,709851,716296,727929,736469,736807,738284,
        738871,739221,744897,745635,745836,747719,747976,750643,751090,757536,
        758968,767801,769619,769864,772141,776885,778338,778535,785761,787685,
        791886,792793,792865,793208,793298,794285,794566,796022,796753,797097,
        799116,799306,800053,800854,801524,804916,805707,806645,808482,808944,
        809242,810930,811364,811653,812108,812689,813080,813488,813847,814082,
        814898,817058,817721,818983,819516,819740,820049,820073,820553,821000,
        822013,822396,822622,823062,823175,823530,824607,825266,825864,829741,
        830304,831414,831740,834276,834543,836932,837097,838429,840644,802374,
        192328,206651,208870,209884,210510,211135,212208,212527,212938,213781,
        213895,215427,217446,218622,218649,220081,220101,220246,220275,220491,
        220969,221042,221044,221102,221527,221870,222342,222905,223168,223474,
        223514,223640,224017,224127,224418,225149,225472,226715,229984,233188,
        235530,235678,239698,246229,246422,247747,248694,252919,256377,256698,
        257621,257710,258288,259009,265389,266285,269506,270964,272441,273942,
        276968,277784,278117,279384,279674,280373,280375,280451,281406,281479,
        281718,281837,281884,282254,282283,282733,283170,283419,283497,283647,
        283947,284343,286083,292256,284608,295130,305510,306686,307980,308681,
        309916,320151,337072,344391,344562,347172,349015,354635,379929,427991,
        436438,443691,458471,528580,671184,710159,737285,783872,786836,787865,
        799432,801541,802074,802743,803185
    ))
    AND NOT (fonte = 'comissao_rep_select' AND sk_contract IN (
        475046,476224,478033,478836,534585,582913,664379,675071,686511,688427,
        705936,708436,714820,716310,718880,727670,730615,737285,739361,743395,
        749956,763457,764894,766349,766856,767073,768923,777934,783699,794150,
        797102,799900,800256,801177,806092,818472
    ))
    AND NOT (fonte = 'corretor_ciq_estornos' AND sk_contract IN (
        235802,236945,237688,241602,243939,244055,245272,246227,248012,248209,
        248333,248440,248958,249611,250161,253030,253192,253367,254074,255207,
        255457,255492,255846,257348,262150,263595,264128,264277,265662,269233,
        270559,270600,271385,276888,284109
    ))
ORDER BY fonte ASC, sk_contract ASC, id_entry ASC
