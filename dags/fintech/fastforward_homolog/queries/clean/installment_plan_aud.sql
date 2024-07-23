SELECT
    id as id_installment_plan,
    rev,
    revtype as rev_type,
    revend as rev_end,
    number_of_installments as installments,
    interest_rate,
    min_installment_value
FROM
    datalake_fastforward_homolog_raw.installment_plan_aud
