WITH scr_base AS (
    SELECT
        cpf,
        rev_end,
        mob,
        reference_date,
        financial_institution_count,
        start_relationship_date,
        ts_created,
        ts_updated,
        ts_next_updated,
        has_scr_attributes,
        CAST(modality AS INT) AS modality,
        CAST(submodality AS INT) AS submodality,
        CAST(domain AS INT) AS domain,
        CAST(value AS DOUBLE) AS value
    FROM
        scr_attributes
    WHERE
        mob <= 6
)
SELECT
    cpf,
    rev_end,
    mob,
    reference_date,
    financial_institution_count,
    start_relationship_date,
    /* =========================
       BALANCE DUE (AGG)
       ========================= */
    -- credit cards (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,110),(2,10,110),(2,18,110),(4,6,110),(13,4,110)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_cards_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,120),(2,4,130),(2,4,140),
                (2,10,120),(2,10,130),(2,10,140),
                (2,18,120),(2,18,130),(2,18,140),
                (4,6,120),(4,6,130),(4,6,140),
                (13,4,120),(13,4,130),(13,4,140)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_cards_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,150),(2,10,150),(2,18,150),(4,6,150),(13,4,150),
                (2,4,160),(2,10,160),(2,18,160),(4,6,160),(13,4,160),
                (2,4,165),(2,10,165),(2,18,165),(4,6,165),(13,4,165),
                (2,4,170),(2,10,170),(2,18,170),(4,6,170),(13,4,170),
                (2,4,175),(2,10,175),(2,18,175),(4,6,175),(13,4,175),
                (2,4,180),(2,10,180),(2,18,180),(4,6,180),(13,4,180),
                (2,4,190),(2,10,190),(2,18,190),(4,6,190),(13,4,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_cards_over_180_days,
    -- real estate (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((9,1,110),(9,2,110)) THEN value
            ELSE 0
        END) AS balance_due_on_real_estate_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (9,1,120),(9,2,120),
                (9,1,130),(9,2,130),
                (9,1,140),(9,2,140)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_real_estate_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (9,1,150),(9,2,150),
                (9,1,160),(9,2,160),
                (9,1,165),(9,2,165),
                (9,1,170),(9,2,170),
                (9,1,175),(9,2,175),
                (9,1,180),(9,2,180),
                (9,1,190),(9,2,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_real_estate_over_180_days,
    -- payroll loan (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,2,110)) THEN value
            ELSE 0
        END) AS balance_due_on_payroll_loan_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,2,120),(2,2,130),(2,2,140)) THEN value
            ELSE 0
        END) AS balance_due_on_payroll_loan_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,2,150),(2,2,160),(2,2,165),(2,2,170),(2,2,175),(2,2,180),(2,2,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_payroll_loan_over_180_days,
    -- vehicles (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((4,1,110)) THEN value
            ELSE 0
        END) AS balance_due_on_vehicles_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((4,1,120),(4,1,130),(4,1,140)) THEN value
            ELSE 0
        END) AS balance_due_on_vehicles_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (4,1,150),(4,1,160),(4,1,165),(4,1,170),(4,1,175),(4,1,180),(4,1,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_vehicles_over_180_days,
    -- home equity (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,11,110)) THEN value
            ELSE 0
        END) AS balance_due_on_home_equity_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,11,120),(2,11,130),(2,11,140)) THEN value
            ELSE 0
        END) AS balance_due_on_home_equity_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,11,150),(2,11,160),(2,11,165),(2,11,170),(2,11,175),(2,11,180),(2,11,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_home_equity_over_180_days,
    -- personal credit (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,110)) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,120),(2,3,130),(2,3,140)) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,3,150),(2,3,160),(2,3,165),(2,3,170),(2,3,175),(2,3,180),(2,3,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_over_180_days,
    -- overdraft check (agg)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((1,1,110),(2,13,110)) THEN value
            ELSE 0
        END) AS balance_due_on_overdraft_check_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (1,1,120),(2,13,120),
                (1,1,130),(2,13,130),
                (1,1,140),(2,13,140)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_overdraft_check_31_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (1,1,150),(2,13,150),
                (1,1,160),(2,13,160),
                (1,1,165),(2,13,165),
                (1,1,170),(2,13,170),
                (1,1,175),(2,13,175),
                (1,1,180),(2,13,180),
                (1,1,190),(2,13,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_overdraft_check_over_180_days,
    /* =========================
       OVERDUE BALANCES (AGG)
       ========================= */
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,205),(2,4,210),
                (2,10,205),(2,10,210),
                (2,18,205),(2,18,210),
                (4,6,205),(4,6,210),
                (13,4,205),(13,4,210)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_credit_cards_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,220),(2,4,230),(2,4,240),(2,4,245),(2,4,250),(2,4,255),(2,4,260),(2,4,270),(2,4,280),(2,4,290),
                (2,10,220),(2,10,230),(2,10,240),(2,10,245),(2,10,250),(2,10,255),(2,10,260),(2,10,270),(2,10,280),(2,10,290),
                (2,18,220),(2,18,230),(2,18,240),(2,18,245),(2,18,250),(2,18,255),(2,18,260),(2,18,270),(2,18,280),(2,18,290),
                (4,6,220),(4,6,230),(4,6,240),(4,6,245),(4,6,250),(4,6,255),(4,6,260),(4,6,270),(4,6,280),(4,6,290),
                (13,4,220),(13,4,230),(13,4,240),(13,4,245),(13,4,250),(13,4,255),(13,4,260),(13,4,270),(13,4,280),(13,4,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_credit_cards_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((9,1,205),(9,1,210),(9,2,205),(9,2,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_real_estate_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (9,1,220),(9,1,230),(9,1,240),(9,1,245),(9,1,250),(9,1,255),(9,1,260),(9,1,270),(9,1,280),(9,1,290),
                (9,2,220),(9,2,230),(9,2,240),(9,2,245),(9,2,250),(9,2,255),(9,2,260),(9,2,270),(9,2,280),(9,2,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_real_estate_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,2,205),(2,2,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_payroll_loan_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,2,220),(2,2,230),(2,2,240),(2,2,245),(2,2,250),(2,2,255),(2,2,260),(2,2,270),(2,2,280),(2,2,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_payroll_loan_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((4,1,205),(4,1,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_vehicles_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (4,1,220),(4,1,230),(4,1,240),(4,1,245),(4,1,250),(4,1,255),(4,1,260),(4,1,270),(4,1,280),(4,1,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_vehicles_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,11,205),(2,11,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_home_equity_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,11,220),(2,11,230),(2,11,240),(2,11,245),(2,11,250),(2,11,255),(2,11,260),(2,11,270),(2,11,280),(2,11,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_home_equity_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,205),(2,3,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_personal_credit_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,3,220),(2,3,230),(2,3,240),(2,3,245),(2,3,250),(2,3,255),(2,3,260),(2,3,270),(2,3,280),(2,3,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_personal_credit_over_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (1,1,205),(1,1,210),
                (2,13,205),(2,13,210)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_overdraft_check_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (1,1,220),(1,1,230),(1,1,240),(1,1,245),(1,1,250),(1,1,255),(1,1,260),(1,1,270),(1,1,280),(1,1,290),
                (2,13,220),(2,13,230),(2,13,240),(2,13,245),(2,13,250),(2,13,255),(2,13,260),(2,13,270),(2,13,280),(2,13,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_overdraft_check_over_30_days,
    /* =========================
       LIMIT EXPIRATION
       ========================= */
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,1,20)) THEN value
            ELSE 0
        END) AS global_limit_expiration_up_to_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,2,20)) THEN value
            ELSE 0
        END) AS overdraft_check_limit_expiration_up_to_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,4,20)) THEN value
            ELSE 0
        END) AS credit_card_limit_expiration_up_to_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,6,20)) THEN value
            ELSE 0
        END) AS personal_credit_limit_expiration_up_to_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,1,40)) THEN value
            ELSE 0
        END) AS global_limit_expiration_over_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,2,40)) THEN value
            ELSE 0
        END) AS overdraft_check_limit_expiration_over_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,4,40)) THEN value
            ELSE 0
        END) AS credit_card_limit_expiration_over_360_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((19,6,40)) THEN value
            ELSE 0
        END) AS personal_credit_limit_expiration_over_360_days,
    /* =========================
       OTHER LOANS (BALANCE + OVERDUE)
       ========================= */
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,99,110)) THEN value
            ELSE 0
        END) AS balance_due_on_other_loans_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,99,120)) THEN value
            ELSE 0
        END) AS balance_due_on_other_loans_31_to_60_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,99,130)) THEN value
            ELSE 0
        END) AS balance_due_on_other_loans_61_to_90_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,99,140)) THEN value
            ELSE 0
        END) AS balance_due_on_other_loans_91_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,99,150),(2,99,160),(2,99,165),(2,99,170),(2,99,175),(2,99,180),(2,99,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_other_loans_over_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,99,205),(2,99,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_other_loans_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,99,220),(2,99,230),(2,99,240),(2,99,245),(2,99,250),(2,99,255),(2,99,260),(2,99,270),(2,99,280),(2,99,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_other_loans_over_30_days,

    /* =========================
       DETAILED CREDIT CARD TYPES (as in original)
       ========================= */
    -- linked rotating credit (2,4,xxx)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,110)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_linked_rotating_credit_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,120)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_linked_rotating_credit_31_to_60_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,130)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_linked_rotating_credit_61_to_90_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,140)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_linked_rotating_credit_91_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,150),(2,4,160),(2,4,165),(2,4,170),(2,4,175),(2,4,180),(2,4,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_linked_rotating_credit_over_180_days,
    -- in store / installments (13,4,xxx)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((13,4,110)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_in_store_or_installments_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((13,4,120)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_in_store_or_installments_31_to_60_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((13,4,130)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_in_store_or_installments_61_to_90_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((13,4,140)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_in_store_or_installments_91_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (13,4,150),(13,4,160),(13,4,165),(13,4,170),(13,4,175),(13,4,180),(13,4,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_in_store_or_installments_over_180_days,
    -- instalment purchase / issuer financed withdrawal (2,10,xxx)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,10,110)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_instalment_purchase_or_issuer_financed_withdrawal_up_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,10,120)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_instalment_purchase_or_issuer_financed_withdrawal_31_to_60_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,10,130)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_instalment_purchase_or_issuer_financed_withdrawal_61_to_90_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,10,140)) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_instalment_purchase_or_issuer_financed_withdrawal_91_to_180_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,10,150),(2,10,160),(2,10,165),(2,10,170),(2,10,175),(2,10,180),(2,10,190)
            ) THEN value
            ELSE 0
        END) AS balance_due_on_credit_card_instalment_purchase_or_issuer_financed_withdrawal_over_180_days,
    -- overdue linked rotating (2,4,2xx)
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,205)) THEN value
            ELSE 0
        END) AS overdue_balance_of_credit_card_linked_rotating_credit_1_to_14_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,4,210)) THEN value
            ELSE 0
        END) AS overdue_balance_of_credit_card_linked_rotating_credit_15_to_30_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN (
                (2,4,220),(2,4,230),(2,4,240),(2,4,245),(2,4,250),(2,4,255),(2,4,260),(2,4,270),(2,4,280),(2,4,290)
            ) THEN value
            ELSE 0
        END) AS overdue_balance_of_credit_card_linked_rotating_credit_over_30_days,
    /* =========================
       PERSONAL CREDIT EXTRA BUCKETS (as in original)
       ========================= */
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,120)) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_31_to_60_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,130)) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_61_to_90_days,
    SUM(CASE
            WHEN has_scr_attributes = 0 THEN NULL
            WHEN (modality, submodality, domain) IN ((2,3,140)) THEN value
            ELSE 0
        END) AS balance_due_on_personal_credit_90_to_180_days,
    /* =========================
       TIMESTAMPS
       ========================= */
    ts_created,
    ts_updated,
    ts_next_updated
FROM
    scr_base
GROUP BY
    cpf,
    rev_end,
    mob,
    reference_date,
    financial_institution_count,
    start_relationship_date,
    ts_created,
    ts_updated,
    ts_next_updated,
    has_scr_attributes
