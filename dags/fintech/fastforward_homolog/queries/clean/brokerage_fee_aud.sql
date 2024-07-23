SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    number_of_rents as rents
FROM
    datalake_fastforward_homolog_raw.brokerage_fee_aud
