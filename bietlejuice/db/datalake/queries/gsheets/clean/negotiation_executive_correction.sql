SELECT
    id_negotiation_executive,
    id_associate_executive,
    incorrect_negociation_executive,
    negotiation_executive,
    executive_position,
    associate_executive,
    hub,
    CAST(dt_month_ref AS DATE) AS dt_month_ref
FROM
    datalake_gsheets_raw.negotiation_executive_correction
