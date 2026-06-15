
WITH deal_delay_rule_e AS (
    SELECT
        id_invoice,
        id_contract,
        dt_closing,
        deal_delay_rule_e,
        bigger_anchor_deal_at_contract,
        delta_days,
        is_contract_with_deal,
        delay_at_deal_creation,
        deal_status,
        delay_contaminated_range_rule_e,
        delay_contamined_range,
        CASE
            WHEN deal_status = 'DEAL IN DELAY'
                THEN delta_days + COALESCE(bigger_anchor_deal_at_contract, 0)
            WHEN deal_status = 'DEAL ON TIME. DELAY AT ANCHOR'
                THEN delay_at_deal_creation
            WHEN deal_status = 'NOT-DEAL' AND is_contract_with_deal = 1 AND delta_days < 0
                THEN delta_days + COALESCE(bigger_anchor_deal_at_contract, 0)
            WHEN deal_status = 'NOT-DEAL' AND is_contract_with_deal = 1 AND delta_days >= 0
                THEN delta_days
            WHEN deal_status = 'NOT-DEAL' AND is_contract_with_deal = 0
                THEN delta_days
        END AS deal_delay_rule_e_calc
    FROM
        datalake_losses.delay
)
SELECT
    id_invoice,
    id_contract,
    dt_closing,
    deal_delay_rule_e,
    bigger_anchor_deal_at_contract,
    delta_days,
    is_contract_with_deal,
    delay_at_deal_creation,
    deal_status,
    delay_contaminated_range_rule_e,
    delay_contamined_range,
    deal_delay_rule_e_calc
FROM
    deal_delay_rule_e
