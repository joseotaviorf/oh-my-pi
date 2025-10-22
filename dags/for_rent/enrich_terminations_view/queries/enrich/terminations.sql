SELECT
  DISTINCT
    ft.sk_termination AS id_termination,
    dt.status AS termination_status,
    dt.category AS termination_category,
    ft.sk_contract AS id_contract,
    ft.sk_house AS id_house,
    ft.sk_house_listing AS id_house_listing,
    fhl.country_code,
    dhl.is_3p_supply,
    ft.ts_termination_request,
    ft.ts_termination_canceled,
    dd.date AS dt_termination,
    dc.dt_ended_rental_confirmed,
    CASE WHEN dc.dt_ended_rental_confirmed IS NOT NULL AND DATE_ADD(DAY, 28, dc.dt_ended_rental_confirmed)<current_date THEN true ELSE false END is_erc_4w_matured,
    tc.is_inspection_required,
    dc.is_exit_inspection_opted_out,
    fhl.sk_next_house_listing_consolidated AS id_next_house_listing,
    dhl2.ts_publication AS ts_publication_next_listing
FROM
  dw_offboarding.fact_terminations AS ft
LEFT JOIN
  dw_offboarding.dim_termination AS dt
    ON ft.sk_termination = dt.sk_termination
LEFT JOIN
  dw_rent.dim_contract AS dc
    ON ft.sk_contract = dc.sk_contract
LEFT JOIN
  dw_public.dim_date AS dd
    ON ft.sk_termination_date=dd.sk_date
LEFT JOIN
  dw_rent.fact_house_listings AS fhl
    ON ft.sk_house_listing = fhl.sk_house_listing
LEFT JOIN
  dw_rent.dim_house_listing AS dhl
    ON fhl.sk_house_listing = dhl.sk_house_listing
LEFT JOIN
  dw_rent.fact_house_listings AS fhl2 
    ON fhl.sk_next_house_listing_consolidated = fhl2.sk_house_listing
LEFT JOIN
  dw_rent.dim_house_listing AS dhl2
    ON fhl2.sk_house_listing = dhl2.sk_house_listing
LEFT JOIN
  datalake_terminator_clean.termination_characteristics AS tc
    ON ft.sk_termination = tc.id_termination