WITH cte_most_recent AS (
    SELECT
        id_proposal,
        MAX(ts_last_updated) AS ts_last_updated
    FROM
        datalake_atta_clean.proposal
    GROUP BY 1
)
SELECT
    p.id_proposal,
    p.id_client,
    p.id_consultant,
    p.id_pre_analysis,
    p.id_emission_provider,
    p.id_franchise,
    p.id_partner,
    p.id_product,
    p.id_offer,
    p.id_proposal_product,
    p.id_multibank_typist_user,
    p.id_proposal_situation,
    p.id_proposal_status,
    p.client_cpf,
    p.client_name,
    p.financing_value,
    p.send_backoffice,
    p.ts_registration,
    p.ts_financing_ended,
    p.ts_last_updated,
    p.year,
    p.month,
    p.day
FROM
    datalake_atta_clean.proposal AS p
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id_proposal = p.id_proposal
        AND cte.ts_last_updated = p.ts_last_updated
