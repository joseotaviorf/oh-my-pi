SELECT
    NULLIF(mes, '') AS month,
    NULLIF(dia, '') AS day,
    NULLIF(cohort, '') AS cohort,
    NULLIF(am, '') AS account_manager,
    NULLIF(context, '') AS context,
    NULLIF(cidade, '') AS city,
    NULLIF(vb, '') AS visit_booked,
    NULLIF(vc, '') AS visit_confirmed,
    NULLIF(os, '') AS offer_signed,
    NULLIF(oa, '') AS offer_accepted,
    NULLIF(ccv, '') AS signed_contract,
    NULLIF(fl, '') AS first_listing,
    NULLIF(ol, '') AS ongoing_listing
FROM
    datalake_gsheets_raw.rede_performance_targets