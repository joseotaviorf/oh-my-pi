SELECT
    COALESCE(pp.id_proposal,-1) AS sk_proposal,
    COALESCE(pr.id_product,-1) AS sk_product,
    COALESCE(pp.id_proposal_status,-1) AS sk_proposal_status,
    COALESCE(pp.id_proposal_situation,-1) AS sk_proposal_situation,
    ppi.id_itau AS sk_proprosal_bank,
    pr.product_name,
    f.provider_name AS financing_bank,
    pp.id_credit_analyst AS sk_credit_analyst,
    pp.id_juridical_analyst AS sk_juridical_analyst,
    CASE
        WHEN COALESCE(proposal_dates.ts_min_credit_application_approval, proposal_dates.ts_min_credit_application_reproval) IS NULL THEN 'Incomplete'
        WHEN proposal_dates.ts_min_credit_application_reproval IS NULL THEN 'Approved'
        WHEN proposal_dates.ts_min_credit_application_approval IS NULL THEN 'Reproved'
        WHEN proposal_dates.ts_max_credit_application_reproval >= proposal_dates.ts_max_credit_application_approval THEN 'Reproved'
        WHEN proposal_dates.ts_max_credit_application_reproval < proposal_dates.ts_max_credit_application_approval THEN 'Approved'
    END AS credit_application_status,
    pre.proposal_status,
    CASE pp.id_proposal_situation
        WHEN 1 THEN 'Andamento'
        WHEN 2 THEN 'Aprovado'
        WHEN 3 THEN 'Pendente'
        WHEN 4 THEN 'Reprovado'
        WHEN 5 THEN 'Cancelada'
        WHEN 6 THEN 'Finalizada'
        WHEN 7 THEN 'Em Análise'
        WHEN 8 THEN 'Análise Atta'
        WHEN 9 THEN 'Análise Banco'
        WHEN 10 THEN 'Análise Banco Duvida'
        WHEN 11 THEN 'Não Passível Defesa'
        WHEN 12 THEN 'Revisão'
        WHEN 13 THEN 'Não Processado Banco'
    END AS proposal_situation,
    CASE
        WHEN p.wallet LIKE'QuintoAndar%' OR p.wallet = 'Casa Mineira' OR p.partner_name LIKE 'Franquia%' THEN 'Canal 5A'
        WHEN p.wallet = 'Other partnerships' AND pp.id_franchise > 0 AND pp.id_franchise NOT IN (1, 182) AND f.franchise_name NOT LIKE '%5A%' THEN 'Canal Franquia'
        WHEN p.wallet = 'Other partnerships' AND pp.id_franchise IN (1, 182) THEN 'Canal Jardins'
    END AS channel,
    COALESCE(conf.house_sale_value, cs.house_value) AS house_value,
    COALESCE(conf.bank_valuation_value, ppi.estimated_house_value) AS house_value_bank_evaluation,
    COALESCE(conf.down_payment_own_resources_value, ppi.down_payment_value, cs.house_value - pp.financing_value, cs.down_payment_amount) AS down_payment_amount,
    COALESCE(conf.financing_value, ppi.finance_value, pp.financing_value, cs.financing_value) AS financing_value,
    (COALESCE(conf.financing_value, ppi.finance_value, pp.financing_value, cs.financing_value) + COALESCE(conf.itbi_value, 0) + COALESCE(conf.bank_valuation_fee_value, 0)) AS total_financing_value,
    conf.itbi_value,
    conf.bank_valuation_fee_value,
    CASE
        WHEN pp.created_by = 30001 THEN TRUE ELSE FALSE
    END AS is_automatic_proposal,
    CASE
        WHEN dsa.is_ccv_canceled = true THEN true
        WHEN fo.sk_offer_rescued_date > fo.sk_offer_dismissed_date THEN false
        WHEN fo.sk_offer_dismissed_date > 0 THEN true
        WHEN fo.sk_offer_dismissed_date < 0 THEN false
    END AS is_offer_canceled,
    NOW()       AS ts_load
FROM datalake_atta_clean.proposal AS pp
LEFT JOIN
    datalake_atta_clean.pre_analysis AS cs
        ON pp.id_pre_analysis = cs.id_pre_analysis
LEFT JOIN
    datalake_atta_clean.product_info AS pr
        ON pp.id_product = pr.id_product
LEFT JOIN
    datalake_atta_clean.track_step_detail AS pre
        ON pre.decision_number = pp.id_proposal_status AND pre.id_product = pr.id_product
LEFT JOIN
    datalake_atta_clean.providers_info AS f
        ON pp.id_emission_provider = f.id_provider
LEFT JOIN
    datalake_atta_clean.financing_proposal AS ppi
        ON pp.id_proposal_product = ppi.id_proposal_product
LEFT JOIN
    datalake_atta_clean.financing_proposal_check AS conf
        ON pp.id_proposal_product = conf.id_proposal_product
LEFT JOIN
    datalake_atta.proposal_dates
        ON pp.id_proposal = proposal_dates.id_proposal
LEFT JOIN
    dw_sale.fact_offers AS fo
        ON COALESCE(cs.id_offer, pp.id_offer) = fo.sk_offer
LEFT JOIN
    dw_sale.dim_sale_agreement AS dsa
        ON COALESCE(cs.id_offer, pp.id_offer) = dsa.sk_offer
LEFT JOIN
    datalake_atta.partner_info AS p
        ON pp.id_partner = p.id_partner
LEFT JOIN
    datalake_atta_clean.franchise_info AS f
        ON pp.id_franchise = f.id_franchise
