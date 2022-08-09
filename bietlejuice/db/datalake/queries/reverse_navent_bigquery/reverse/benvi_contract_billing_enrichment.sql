WITH mexico_contracts AS (
  SELECT
      c.id_contract,
      c.country_code,
      c.signature_type,
      c.type,
      c.status,
      c.condo_payer,
      c.condo_responsible,
      c.rental_administrator,
      c.day_month_due,
      c.rent AS contract_rent,
      c.first_rent_charged,
      c.guarantee,
      c.rental_insurance_installments,
      c.rental_insurance_value,
      c.monthly_administration_fee,
      c.tenant_service_fee,
      c.iptu,
      c.closing_status,
      c.cancellation_reason,
      c.dt_start,
      c.dt_entrance,
      c.dt_intended_end,
      c.dt_annulment
  FROM
    dw_public.dim_contract AS c
  WHERE
    country_code = 'MX'
)
SELECT
    c.country_code,
    c.id_contract,
    c.signature_type,
    c.type,
    c.status,
    c.condo_payer,
    c.condo_responsible,
    c.rental_administrator, 
    /* Owner information */
    f.sk_owner,
    '' AS owner_name,
    uo.sexo AS owner_gender,
    uo.houses_owned,
    uo.active AS flag_owner_active,
    uo.bloqueado AS flag_owner_locked,
    dpo.has_ongoing_contract AS owner_has_ongoing_contract,
    '' AS owner_cpf,
    '' AS owner_email,
    '' AS owner_main_phone,
    /* Client information */
    f.sk_client,
    '' AS tenant_name,
    ut.sexo AS tenant_gender,
    ut.visits_booked,
    ut.visits_realized,
    ut.visits_expected_to_happen,
    ut.active AS flag_tenant_activo,
    ut.bloqueado AS flag_tenant_locked,
    dpt.has_ongoing_contract AS tenat_has_ongoing_contract,
    '' AS tenant_cpf,
    '' AS tenant_email,
    '' AS tenant_main_phone,
    /* Contract details */
    c.day_month_due,
    c.contract_rent,
    c.first_rent_charged,
    c.guarantee,
    c.rental_insurance_installments,
    c.rental_insurance_value,
    c.monthly_administration_fee,
    c.tenant_service_fee,
    c.iptu,
    c.closing_status,
    c.cancellation_reason,
    c.dt_start,
    c.dt_entrance,
    c.dt_intended_end,
    c.dt_annulment,
    /* Listing details */
    f.sk_house_listing,
    l.id_house,
    l.version,
    l.rent AS rent_listing,
    l.house_rent,
    l.house_neighborhood,
    l.house_zipcode,
    l.house_city,
    l.house_complement,
    l.house_condo,
    l.house_elevator,
    l.house_address,
    l.house_iptu,
    l.house_lat,
    l.house_lng,
    l.house_number,
    l.house_bathrooms,
    l.house_suites,
    l.house_garages,
    l.house_status,
    l.house_type,
    l.house_entrance,
    l.house_total_value,
    l.house_total_area,
    l.house_construction_area,
    l.house_condo_type,
    l.who_is_living,
    l.key_type,
    l.key_location,
    l.house_predicted_price,
    l.sale_price,
    l.has_visit_restriction,
    l.has_instant_offer_enabled,
    l.is_house_furnished,
    l.is_exclusive,
    l.is_for_rent,
    l.is_for_sale,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    mexico_contracts AS c
JOIN
    dw_public.fact_listing_rent_flows AS f 
        ON c.id_contract = f.sk_contract
JOIN
    dw_public.dim_house_listing AS l
        ON l.sk_house_listing = f.sk_house_listing
LEFT JOIN
    dw_quintoandar.fact_contract_people AS cpo 
        ON c.id_contract = cpo.sk_contract
        AND cpo.is_contract_user = TRUE
        AND cpo.contract_role = 'landlord'
LEFT JOIN
    dw_quintoandar.dim_contract_person AS dpo
        ON cpo.sk_contract_person = dpo.sk_contract_person
LEFT JOIN
    dw_quintoandar.fact_contract_people AS cpt 
        ON c.id_contract = cpt.sk_contract
        AND cpt.is_contract_user = True
        AND cpt.contract_role = 'tenant'
LEFT JOIN
    dw_quintoandar.dim_contract_person AS dpt
        ON cpt.sk_contract_person = dpt.sk_contract_person
JOIN
    dw_public.dim_user AS uo 
        ON uo.sk_user = f.sk_owner
JOIN
    dw_public.dim_user AS ut
        ON ut.sk_user = f.sk_client