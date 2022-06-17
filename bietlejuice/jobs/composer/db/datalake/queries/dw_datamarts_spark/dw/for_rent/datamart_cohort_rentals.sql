WITH all_listings AS (
    SELECT
        rf.sk_house_listing,
        dhl.id_house,
        rf.sk_contract,
        dhl.ts_publication,
        dhl.listing_category_start,
        rf.days_house_listing_to_contract_signed,
        dc.ts_signature,
        COALESCE(DATE(REPLACE(REPLACE(REPLACE(dc.dt_start,'0019','2019'),'2009','2019'),'0020','2020')), dc.dt_entrance) AS dt_start,
        dc.dt_annulment,
        dc.status,
        dc.rent AS value_rent,
        dc.first_rental_commission,
        cfull.monthly_administration_fee AS admin_fee,
        dr.city_group,
        dr.city_name,
        ROW_NUMBER() OVER (PARTITION BY dhl.id_house ORDER BY dc.dt_start) AS order_contracts,
        ROW_NUMBER() OVER (PARTITION BY dhl.id_house, rf.sk_contract ORDER BY dc.dt_start) AS dupli_contracts,
        LEAD(dhl.ts_publication, 1) OVER (PARTITION BY dhl.id_house ORDER BY rf.sk_house_listing) AS next_listing,
        LEAD(dc.dt_start, 1) OVER (PARTITION BY dhl.id_house ORDER BY rf.sk_house_listing) AS next_contract,
        COUNT(rf.sk_house_listing) OVER (PARTITION BY dhl.id_house) AS total_listings,
        MIN(dc.dt_start) OVER (PARTITION BY dhl.id_house) AS first_dt_start
    FROM
        dw_public.dim_contract AS dc
    LEFT JOIN
        dw_public.fact_listing_rent_flows AS rf
            ON dc.sk_contract = rf.sk_contract
            AND (rf.sk_contract_signed_date > 0
                OR rf.sk_contract_created_date > 0
                )
    LEFT JOIN
        dw_public.dim_house_listing AS dhl -- bring information about the listing
            ON rf.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN
        dw_public.dim_region AS dr -- bring information from city_group
            ON rf.sk_region = dr.sk_region
    LEFT JOIN
        datalake_ebdb_clean.full_contract AS cfull -- bring administration fee
            ON cfull.id = dc.sk_contract
    WHERE
        dc.status IN ('Ativo', 'Finalizado') -- consider only active or ended contracts
        AND (dc.dt_start <= dc.dt_annulment
            OR dc.dt_annulment IS NULL
            ) --Ignore contracts that have dt_anullment before dt_start
),
all_first_contracts AS (
    SELECT
        city_group,
        city_name,
        DATE_TRUNC('month', dt_start) AS contract_start_month,
        dt_start,
        DATE_TRUNC('month',dt_annulment) AS contract_end_month,
        dt_annulment,
        dd.date,
        dd.month_start,
        sk_house_listing,
        sk_contract,
        id_house,
        value_rent,
        admin_fee
    FROM
        all_listings AS al
    JOIN
        dw_public.dim_date AS dd
            ON dd.date BETWEEN al.dt_start
            AND COALESCE(dt_annulment, DATE_ADD(CURRENT_DATE,-1))
    WHERE
        order_contracts = 1
        AND sk_contract > 0
        AND dupli_contracts = 1
        AND dd.date <= CURRENT_DATE
    ORDER BY 1 DESC
),
all_next_contracts AS (
    SELECT
        city_group,
        city_name,
        DATE_TRUNC('month', first_dt_start) AS contract_first_start_month,
        first_dt_start,
        DATE_TRUNC('month', dt_start) AS contract_start_month,
        dt_start,
        DATE_TRUNC('month',dt_annulment) AS contract_end_month,
        dt_annulment,
        dd.date,
        dd.month_start,
        sk_house_listing,
        id_house,
        value_rent,
        admin_fee
    FROM
        all_listings AS al
    JOIN
    dw_public.dim_date AS dd
        ON dd.date BETWEEN al.dt_start
        AND COALESCE(al.dt_annulment, DATE_ADD(CURRENT_DATE,-1))
    WHERE
        order_contracts > 1
        AND sk_contract > 0
        AND dupli_contracts = 1
        AND dd.date <= CURRENT_DATE
    ORDER BY 1 DESC),
    all_first_rentals AS (
    SELECT
        city_group,
        DATE_FORMAT(contract_start_month, "yyyy-MM-dd") AS contract_start_month,
        MONTHS_BETWEEN(month_start, contract_start_month) AS months_after_first_contract,
        COUNT(DISTINCT id_house) AS total_first_rentals
    FROM
        all_first_contracts
    GROUP BY 1, 2, 3
),
all_re_rentals AS (
    SELECT
        city_group,
        DATE_FORMAT(contract_first_start_month, "yyyy-MM-dd") AS contract_start_month,
        MONTHS_BETWEEN(month_start, contract_first_start_month) AS months_after_first_contract,
        COUNT(DISTINCT id_house) AS total_re_rentals
    FROM
        all_next_contracts
    GROUP BY 1, 2, 3
),
all_ended_re_rentals AS (
    SELECT
        city_group,
        DATE_FORMAT(anc.contract_first_start_month, "yyyy-MM-dd") AS contract_start_month,
        MONTHS_BETWEEN(anc.contract_end_month, anc.contract_first_start_month) AS months_between_first_contract_and_ended,
        COUNT(DISTINCT anc.id_house) AS total_ended_re_rentals
    FROM
        all_next_contracts AS anc
    WHERE
        anc.contract_end_month IS NOT NULL
    GROUP BY 1, 2, 3 
),
all_first_contract_rent AS (
    SELECT
        city_group,
        contract_start_month,
        months_after_first_contract,
        AVG(value_rent) AS avg_value_rent_first_rentals
    FROM 
        (
        SELECT DISTINCT
            city_group,
            DATE_FORMAT(contract_start_month, "yyyy-MM-dd") AS contract_start_month,
            MONTHS_BETWEEN(month_start, contract_start_month) AS months_after_first_contract,
            id_house,
            value_rent
        FROM
            all_first_contracts 
        )
    GROUP BY 1, 2, 3 
),
all_re_rental_rent AS (
    SELECT
        city_group,
        contract_start_month,
        months_after_first_contract,
        AVG(value_rent) AS avg_value_rent_re_rentals
    FROM
        (
        SELECT DISTINCT
            city_group,
            DATE_FORMAT(contract_first_start_month, "yyyy-MM-dd") AS contract_start_month,
            MONTHS_BETWEEN(month_start, contract_first_start_month) AS months_after_first_contract,
            id_house,
            value_rent
        FROM
            all_next_contracts 
        )
    GROUP BY 1, 2, 3 
),
all_first_contract_adm_fee AS (
    SELECT
        city_group,
        contract_start_month,
        months_after_first_contract,
        AVG(admin_fee) AS avg_admin_fee_first_rentals
    FROM 
        (
        SELECT DISTINCT
            city_group,
            DATE_FORMAT(contract_start_month, "yyyy-MM-dd") AS contract_start_month,
            MONTHS_BETWEEN(month_start, contract_start_month) AS months_after_first_contract,
            id_house,
            admin_fee
        FROM
            all_first_contracts
        )
    GROUP BY 1, 2, 3 
),
all_re_rental_adm_fee AS (
    SELECT
        city_group,
        contract_start_month,
        months_after_first_contract,
        AVG(admin_fee) AS avg_admin_fee_re_rentals
    FROM 
        (
        SELECT DISTINCT
            city_group,
            DATE_FORMAT(contract_first_start_month, "yyyy-MM-dd") AS contract_start_month,
            MONTHS_BETWEEN(month_start, contract_first_start_month) AS months_after_first_contract,
            id_house,
            admin_fee
        FROM
            all_next_contracts
        )
    GROUP BY 1, 2, 3 
)
SELECT
    fr.city_group,
    fr.contract_start_month,
    fr.months_after_first_contract,
    fr.total_first_rentals,
    rr.total_re_rentals,
    err.total_ended_re_rentals,
    fcr.avg_value_rent_first_rentals,
    fcaf.avg_admin_fee_first_rentals,
    rr_rent.avg_value_rent_re_rentals,
    rr_af.avg_admin_fee_re_rentals,
    CURRENT_TIMESTAMP AS ts_load
FROM
    all_first_rentals AS fr
LEFT JOIN
    all_re_rentals AS rr
        ON fr.city_group = rr.city_group
        AND fr.contract_start_month = rr.contract_start_month
        AND fr.months_after_first_contract = rr.months_after_first_contract
LEFT JOIN
    all_ended_re_rentals AS err
        ON fr.city_group = err.city_group
        AND fr.contract_start_month = err.contract_start_month
        AND fr.months_after_first_contract = err.months_between_first_contract_and_ended
LEFT JOIN
    all_first_contract_rent AS fcr
        ON fr.city_group = fcr.city_group
        AND fr.contract_start_month = fcr.contract_start_month
        AND fr.months_after_first_contract = fcr.months_after_first_contract
LEFT JOIN
    all_first_contract_adm_fee AS fcaf
        ON fr.city_group = fcaf.city_group
        AND fr.contract_start_month = fcaf.contract_start_month
        AND fr.months_after_first_contract = fcaf.months_after_first_contract
LEFT JOIN
    all_re_rental_rent AS rr_rent
        ON fr.city_group = rr_rent.city_group
        AND fr.contract_start_month = rr_rent.contract_start_month
        AND fr.months_after_first_contract = rr_rent.months_after_first_contract
LEFT JOIN
    all_re_rental_adm_fee AS rr_af
        ON fr.city_group = rr_af.city_group
        AND fr.contract_start_month = rr_af.contract_start_month
        AND fr.months_after_first_contract = rr_af.months_after_first_contract
ORDER BY 1, 2 DESC, 3