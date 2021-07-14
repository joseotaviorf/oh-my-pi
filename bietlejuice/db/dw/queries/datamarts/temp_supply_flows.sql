WITH
discard_rene AS (
    WITH context AS (
    SELECT
        id_house_lead,
        CASE
            WHEN business_context = 'SALE' THEN reason
            ELSE NULL
        END AS is_sale,
        CASE
            WHEN business_context = 'RENT' THEN reason
            ELSE NULL
        END AS is_rent
    FROM
        datalake_rene_descartes_clean_prod.lead_rejection
    )
    SELECT
        id_house_lead,
        MAX(is_sale) AS discard_sale,
        MAX(is_rent) AS discard_rent
    FROM
        context
    GROUP BY 1
),
wololo_discard AS (
    WITH unique_wololo AS (
    SELECT distinct
        id_prospect,
        business_context,
        MAX(id) AS id
    FROM
        datalake_wololo_clean_prod.context_discard
    GROUP BY 1, 2
),
context AS (
    SELECT
        u.id_prospect,
        CASE
            WHEN u.business_context = 'SALE' THEN cd.reason
            ELSE NULL
        END AS is_sale,
        CASE
            WHEN u.business_context = 'RENT' THEN cd.reason
            ELSE NULL
        END AS is_rent
    FROM
        datalake_wololo_clean_prod.context_discard cd
    INNER JOIN
        unique_wololo u
        ON u.id = cd.id
        AND u.business_context = cd.business_context
        AND u.id_prospect = cd.id_prospect
)
    SELECT
        id_prospect,
        MAX(is_sale) discard_sale,
        MAX(is_rent) discard_rent
    FROM
        context
    GROUP BY 1
),
discard_by_context AS (
SELECT
    dl.sk_lead,
    dl.reason,
    dl.reason_detail,
    dl.is_for_rent,
    dl.is_for_sale,
    r.discard_rent AS lead_discard_rent,
    r.discard_sale AS lead_discard_sale,
    w.discard_rent AS prospect_discard_rent,
    w.discard_sale AS prospect_discard_sale
FROM
    dim_lead dl
LEFT JOIN
    datalake_wololo_clean_prod.prospect p
    ON cast(p.id_reference AS varchar) = dl.sk_lead
LEFT JOIN
    wololo_discard w
    ON w.id_prospect = p.id
LEFT JOIN
    discard_rene r
    ON r.id_house_lead = dl.external_id
),
dates_by_context AS (
SELECT
    sk_house_listing_flow,
    sk_house_listing,
    sk_lead,
    sk_region,
    CASE
        WHEN origin_table = 'Rent' THEN mkt_origin
        ELSE NULL
    END AS mkt_origin_rent,
    CASE
        WHEN origin_table = 'Sale' THEN mkt_origin
        ELSE NULL
    END AS mkt_origin_sale,
    CASE
        WHEN origin_table = 'Rent' THEN mkt_completion
        ELSE NULL
    END AS mkt_completion_rent,
    CASE
        WHEN origin_table = 'Sale' THEN mkt_completion
        ELSE NULL
    END AS mkt_completion_sale,
    CASE
        WHEN origin_table = 'Rent' THEN mkt_channel
        ELSE NULL
    END AS mkt_channel_rent,
    CASE
        WHEN origin_table = 'Sale' THEN mkt_channel
        ELSE NULL
    END AS mkt_channel_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sales_company
        ELSE NULL
    END AS sales_company_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sales_company
        ELSE NULL
    END AS sales_company_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sourcing_ops
        ELSE NULL
    END AS sourcing_ops_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sourcing_ops
        ELSE NULL
    END AS sourcing_ops_sale,
    CASE
        WHEN origin_table = 'Rent' THEN lead_origin
        ELSE NULL
    END AS lead_origin_rent,
    CASE
        WHEN origin_table = 'Sale' THEN lead_origin
        ELSE NULL
    END AS lead_origin_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sk_lead_date
        ELSE '-1'
    END AS sk_lead_date_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sk_lead_date
        ELSE '-1'
    END AS sk_lead_date_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sk_prospect_date
        ELSE '-1'
    END AS sk_prospect_date_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sk_prospect_date
        ELSE '-1'
    END AS sk_prospect_date_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sk_qualified_date
        ELSE '-1'
    END AS sk_qualified_date_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sk_qualified_date
        ELSE '-1'
    END AS sk_qualified_date_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sk_opportunity_date
        ELSE '-1'
    END AS sk_opportunity_date_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sk_opportunity_date
        ELSE '-1'
    END AS sk_opportunity_date_sale,
    CASE
        WHEN origin_table = 'Rent' THEN sk_first_listing_date
        ELSE '-1'
    END AS sk_first_listing_date_rent,
    CASE
        WHEN origin_table = 'Sale' THEN sk_first_listing_date
        ELSE '-1'
    END AS sk_first_listing_date_sale,
    CASE
        WHEN origin_table = 'Rent' THEN context_first_listing
        ELSE NULL
    END AS context_first_listing_rent,
    CASE
        WHEN origin_table = 'Sale' THEN context_first_listing
        ELSE NULL
    END AS context_first_listing_sale
FROM
    datamarts.lead_listing_flows
),
max_dates AS (
SELECT
    sk_house_listing_flow,
    sk_house_listing,
    sk_lead,
    sk_region,
    MAX(mkt_origin_rent) AS mkt_origin_rent,
    MAX(mkt_origin_sale) AS mkt_origin_sale,
    MAX(mkt_completion_rent) AS mkt_completion_rent,
    MAX(mkt_completion_sale) AS mkt_completion_sale,
    MAX(mkt_channel_rent) AS mkt_channel_rent,
    MAX(mkt_channel_sale) AS mkt_channel_sale,
    MAX(sales_company_rent) AS sales_company_rent,
    MAX(sales_company_sale) AS sales_company_sale,
    MAX(sourcing_ops_rent) AS sourcing_ops_rent,
    MAX(sourcing_ops_sale) AS sourcing_ops_sale,
    MAX(lead_origin_rent) AS lead_origin_rent,
    MAX(lead_origin_sale) AS lead_origin_sale,
    MAX(sk_lead_date_rent) AS sk_lead_date_rent,
    MAX(sk_lead_date_sale) AS sk_lead_date_sale,
    MAX(sk_prospect_date_rent) AS sk_prospect_date_rent,
    MAX(sk_prospect_date_sale) AS sk_prospect_date_sale,
    MAX(sk_qualified_date_rent) AS sk_qualified_date_rent,
    MAX(sk_qualified_date_sale) AS sk_qualified_date_sale,
    MAX(sk_opportunity_date_rent) AS sk_opportunity_date_rent,
    MAX(sk_opportunity_date_sale) AS sk_opportunity_date_sale,
    MAX(sk_first_listing_date_rent) AS sk_first_listing_date_rent,
    MAX(sk_first_listing_date_sale) AS sk_first_listing_date_sale,
    MAX(context_first_listing_rent) AS context_first_listing_rent,
    MAX(context_first_listing_sale) AS context_first_listing_sale
FROM
    dates_by_context
GROUP BY 1,2,3,4
),
hybrid_dates AS ( -- duplicating dates when Calculadora de Aluguel and IndicaAi
SELECT
    sk_house_listing_flow,
    sk_house_listing,
    sk_lead,
    sk_region,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_origin_sale IS NULL THEN mkt_origin_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND mkt_origin_sale IS NULL THEN mkt_origin_rent
        ELSE mkt_origin_sale
    END AS mkt_origin_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_origin_rent IS NULL THEN mkt_origin_sale
        ELSE mkt_origin_rent
    END AS mkt_origin_rent,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_completion_sale IS NULL THEN mkt_completion_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND mkt_completion_sale IS NULL THEN mkt_completion_rent
        ELSE mkt_completion_sale
    END AS mkt_completion_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_completion_rent IS NULL THEN mkt_completion_sale
        ELSE mkt_completion_rent
    END AS mkt_completion_rent,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_channel_sale IS NULL THEN mkt_channel_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND mkt_channel_sale IS NULL THEN mkt_channel_rent
        ELSE mkt_channel_sale
    END AS mkt_channel_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND mkt_channel_rent IS NULL THEN mkt_channel_sale
        ELSE mkt_channel_rent
    END AS mkt_channel_rent,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND sales_company_sale IS NULL THEN sales_company_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND sales_company_sale IS NULL THEN sales_company_rent
        ELSE sales_company_sale
    END AS sales_company_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND sales_company_rent IS NULL THEN sales_company_sale
        ELSE sales_company_rent
    END AS sales_company_rent,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND sourcing_ops_sale IS NULL THEN sourcing_ops_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND sourcing_ops_sale IS NULL THEN sourcing_ops_rent
        ELSE sourcing_ops_sale
    END AS sourcing_ops_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND sourcing_ops_rent IS NULL THEN sourcing_ops_sale
        ELSE sourcing_ops_rent
    END AS sourcing_ops_rent,
    CASE
        WHEN mkt_origin_rent IN ('Indica Aí - General','Indica Aí - Agents') AND lead_origin_sale IS NULL THEN lead_origin_rent
        WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND lead_origin_sale IS NULL THEN lead_origin_rent
        ELSE lead_origin_sale
    END AS lead_origin_sale,
    CASE
        WHEN mkt_origin_sale IN ('Indica Aí - General','Indica Aí - Agents') AND lead_origin_rent IS NULL THEN lead_origin_sale
        ELSE lead_origin_rent
    END AS lead_origin_rent,
    CASE
		WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent= 'Price Calculator' AND sk_lead_date_sale<0  THEN sk_lead_date_rent
		WHEN mkt_origin_rent IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_lead_date_sale<0 THEN sk_lead_date_rent
		ELSE sk_lead_date_sale
	END AS sk_lead_date_sale,
	CASE
		WHEN mkt_origin_sale IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_lead_date_rent<0 THEN sk_lead_date_sale
		ELSE sk_lead_date_rent
	END AS sk_lead_date_rent,
    CASE
		WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent = 'Price Calculator' AND sk_prospect_date_sale<0  THEN sk_prospect_date_rent
		WHEN mkt_origin_rent IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_prospect_date_sale<0 THEN sk_prospect_date_rent
		ELSE sk_prospect_date_sale
	END AS sk_prospect_date_sale,
	CASE
		WHEN mkt_origin_sale IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_prospect_date_rent<0 THEN sk_prospect_date_sale
		ELSE sk_prospect_date_rent
	END AS sk_prospect_date_rent,
	CASE
		WHEN lead_origin_rent = 'PriceSuggestion' AND mkt_origin_rent = 'Price Calculator' AND sk_qualified_date_sale<0  THEN sk_qualified_date_rent
		WHEN mkt_origin_rent IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_qualified_date_sale<0 THEN sk_qualified_date_rent
		ELSE sk_qualified_date_sale
	END AS sk_qualified_date_sale,
	CASE
		WHEN mkt_origin_sale IN ('Indica Aí - General', 'Indica Aí - Agents') AND sk_qualified_date_rent<0 THEN sk_qualified_date_sale
		ELSE sk_qualified_date_rent
	END AS sk_qualified_date_rent,
	sk_opportunity_date_sale,
	sk_opportunity_date_rent,
	sk_first_listing_date_sale,
	sk_first_listing_date_rent,
	context_first_listing_sale,
	context_first_listing_rent
FROM
    max_dates
),
dates_filters AS (
SELECT
    llf.sk_house_listing_flow,
    llf.sk_house_listing,
    llf.sk_lead,
    llf.sk_region,
    llf.mkt_origin_rent,
    llf.mkt_origin_sale,
    llf.mkt_completion_rent,
    llf.mkt_completion_sale,
    llf.mkt_channel_rent,
    llf.mkt_channel_sale,
    llf.sales_company_rent,
    llf.sales_company_sale,
    llf.sourcing_ops_rent,
    llf.sourcing_ops_sale,
    llf.lead_origin_rent,
    llf.lead_origin_sale,
    llf.sk_lead_date_rent,
    llf.sk_lead_date_sale,
    CASE -- filtering prospect rent
		WHEN lead_discard_rent IN ('HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS', 'ForaArea','DUPLICATED_LEAD','CONTACT_ON_BLOCK_LIST') THEN '-1'
		ELSE sk_prospect_date_rent
	END sk_prospect_date_rent,
	CASE -- filtering prospect sale
		WHEN lead_discard_sale IN ('HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS', 'ForaArea','DUPLICATED_LEAD','CONTACT_ON_BLOCK_LIST') THEN '-1'
		ELSE sk_prospect_date_sale
	END sk_prospect_date_sale,
	CASE -- filtering qualified rent
	    WHEN prospect_discard_rent IN ('CONTACT_DIDNT_EXIST','HOUSE_ALREADY_PUBLISHED','CONTACT_KNOW_OWNER','CONTACT_WASNT_THE_HOUSE_OWNER','HOUSE_ALREADY_SOLD',
	    'HOUSE_WAS_A_BUSINESS_REAL_ESTATE','HOUSE_WITH_BAD_CONDITIONS','OWNER_DIDNT_ANSWER_PHONE','OWNER_DIDNT_LISTEN_TO_PITCH','OWNER_DIDNT_WANT_RECEIVE_CALL',
	    'PROPERTY_IN_OFFPLANT','HOUSE_PRICE_WAS_OUT_OF_BOUNDS','ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING','HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS') THEN '-1'
	    ELSE sk_qualified_date_rent
	END sk_qualified_date_rent,
	CASE -- filtering qualified sale
	    WHEN prospect_discard_sale IN ('CONTACT_DIDNT_EXIST','HOUSE_ALREADY_PUBLISHED','CONTACT_KNOW_OWNER','CONTACT_WASNT_THE_HOUSE_OWNER','HOUSE_ALREADY_SOLD',
	    'HOUSE_WAS_A_BUSINESS_REAL_ESTATE','HOUSE_WITH_BAD_CONDITIONS','OWNER_DIDNT_ANSWER_PHONE','OWNER_DIDNT_LISTEN_TO_PITCH','OWNER_DIDNT_WANT_RECEIVE_CALL',
	    'PROPERTY_IN_OFFPLANT','HOUSE_PRICE_WAS_OUT_OF_BOUNDS','HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS') THEN '-1'
	    ELSE sk_qualified_date_sale
	END sk_qualified_date_sale,
	CASE -- filtering opportunity rent
	    WHEN prospect_discard_rent IN ('HOUSE_ALREADY_RENTED_AVAILABLE_IN_1_MONTH','HOUSE_ALREADY_RENTED_AVAILABLE_IN_3_MONTHS','HOUSE_UNDER_EXCLUSIVITY_CONTRACT','OWNER_WITH_PRIME_PROFILE',
	    'OWNER_DISAGREE_CHARGES_PAYMENTS','OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH','OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH','OWNER_DIDNT_WANT_ADMINISTRATION','ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS') THEN '-1'
	    ELSE sk_opportunity_date_rent
	END sk_opportunity_date_rent,
	CASE -- filtering opportunity sale
	    WHEN prospect_discard_sale IN ('HOUSE_UNDER_EXCLUSIVITY_CONTRACT','OWNER_WITH_PRIME_PROFILE','OWNER_DISAGREE_CHARGES_PAYMENTS','OWNER_DISAGREE_PAYMENT_TIMING','ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS') THEN '-1'
	    ELSE sk_opportunity_date_sale
	END sk_opportunity_date_sale,
	llf.sk_first_listing_date_sale,
	llf.sk_first_listing_date_rent,
	llf.context_first_listing_sale,
	llf.context_first_listing_rent,
	dc.lead_discard_sale,
	dc.lead_discard_rent,
	dc.prospect_discard_sale,
	dc.prospect_discard_rent
FROM
    hybrid_dates llf
LEFT JOIN
    discard_by_context dc
    ON llf.sk_lead = dc.sk_lead
),
available_qualified AS (
SELECT
    llf.sk_house_listing_flow,
    llf.sk_house_listing,
    llf.sk_lead,
    llf.sk_region,
    llf.mkt_origin_rent,
    llf.mkt_origin_sale,
    llf.mkt_completion_rent,
    llf.mkt_completion_sale,
    llf.mkt_channel_rent,
    llf.mkt_channel_sale,
    llf.sales_company_rent,
    llf.sales_company_sale,
    llf.sourcing_ops_rent,
    llf.sourcing_ops_sale,
    llf.lead_origin_rent,
    llf.lead_origin_sale,
    llf.sk_lead_date_rent,
    llf.sk_lead_date_sale,
    llf.sk_prospect_date_rent,
	llf.sk_prospect_date_sale,
	llf.sk_qualified_date_rent,
	llf.sk_qualified_date_sale,
	CASE -- filtering available qualified rent
	    WHEN prospect_discard_rent IN ('HOUSE_ALREADY_RENTED_AVAILABLE_IN_6_MONTHS','HOUSE_ALREADY_RENTED_AVAILABLE_IN_MORE_THAN_6_MONTHS','HOUSE_ALREADY_RENTED','OWNER_GAVE_UP_RENTING','SEASONAL_RENT','HOUSE_UNDER_MAJOR_RENOVATION') THEN '-1'
	    ELSE sk_qualified_date_rent
	END AS sk_available_qualified_date_rent,
	CASE -- filtering available qualified sale
	    WHEN prospect_discard_sale IN ('OWNER_GAVE_UP_SELLING','ISSUES_WITH_HOUSE_DOCUMENTATION','PROPERTY_IN_JUDICIAL_INVENTORY') THEN '-1'
	    ELSE sk_qualified_date_sale
	END AS sk_available_qualified_date_sale,
	llf.sk_opportunity_date_rent,
	llf.sk_opportunity_date_sale,
	llf.sk_first_listing_date_sale,
	llf.sk_first_listing_date_rent,
	llf.context_first_listing_sale,
	llf.context_first_listing_rent,
	llf.lead_discard_sale,
	llf.lead_discard_rent,
	llf.prospect_discard_sale,
	llf.prospect_discard_rent
FROM dates_filters llf
)
SELECT
	llf.sk_house_listing_flow,
    llf.sk_lead,
	llf.sk_house_listing,
	llf.sk_region,
    llf.mkt_origin_rent,
    llf.mkt_origin_sale,
    llf.mkt_completion_rent,
    llf.mkt_completion_sale,
    llf.mkt_channel_rent,
    llf.mkt_channel_sale,
    llf.sales_company_rent,
    llf.sales_company_sale,
    llf.sourcing_ops_rent,
    llf.sourcing_ops_sale,
    llf.lead_origin_rent,
    llf.lead_origin_sale,
    llf.sk_lead_date_rent,
    llf.sk_lead_date_sale,
    llf.sk_prospect_date_rent,
    llf.sk_prospect_date_sale,
    llf.sk_qualified_date_rent,
    llf.sk_qualified_date_sale,
    llf.sk_available_qualified_date_rent,
    llf.sk_available_qualified_date_sale,
    llf.sk_opportunity_date_rent,
    llf.sk_opportunity_date_sale,
    llf.sk_first_listing_date_rent,
    llf.sk_first_listing_date_sale,
	CASE
        WHEN sk_lead_date_rent = sk_lead_date_sale AND sk_lead_date_sale>0 AND sk_lead_date_rent>0 THEN 'Hybrid'
        WHEN sk_lead_date_sale >0 AND sk_lead_date_rent != sk_lead_date_sale THEN 'Sale'
    END AS context_lead_sale,
    CASE
        WHEN sk_lead_date_rent = sk_lead_date_sale AND sk_lead_date_sale>0 AND sk_lead_date_rent>0 THEN 'Hybrid'
        WHEN sk_lead_date_rent >0 AND sk_lead_date_rent != sk_lead_date_sale THEN 'Rent'
    END AS context_lead_rent,
    CASE
        WHEN sk_prospect_date_rent = sk_prospect_date_sale AND sk_prospect_date_sale>0 AND sk_prospect_date_rent>0 THEN 'Hybrid'
        WHEN sk_prospect_date_sale >0 AND sk_prospect_date_rent != sk_prospect_date_sale THEN 'Sale'
    END AS context_prospect_sale,
    CASE
        WHEN sk_prospect_date_rent = sk_prospect_date_sale AND sk_prospect_date_sale>0 AND sk_prospect_date_rent>0 THEN 'Hybrid'
        WHEN sk_prospect_date_rent >0 AND sk_prospect_date_rent != sk_prospect_date_sale THEN 'Rent'
    END AS context_prospect_rent,
    CASE
        WHEN sk_qualified_date_rent = sk_qualified_date_sale AND sk_qualified_date_sale>0 AND sk_qualified_date_rent>0 THEN 'Hybrid'
        WHEN sk_qualified_date_sale >0 AND sk_qualified_date_rent != sk_qualified_date_sale THEN 'Sale'
    END AS context_qualified_sale,
    CASE
        WHEN sk_qualified_date_rent = sk_qualified_date_sale AND sk_qualified_date_sale>0 AND sk_qualified_date_rent>0 THEN 'Hybrid'
        WHEN sk_qualified_date_rent >0 AND sk_qualified_date_rent != sk_qualified_date_sale THEN 'Rent'
    END AS context_qualified_rent,
    CASE
        WHEN sk_available_qualified_date_rent = sk_available_qualified_date_sale AND sk_available_qualified_date_sale>0 AND sk_available_qualified_date_rent>0 THEN 'Hybrid'
        WHEN sk_available_qualified_date_sale >0 AND sk_available_qualified_date_rent != sk_available_qualified_date_sale THEN 'Sale'
    END AS context_available_qualified_sale,
    CASE
        WHEN sk_available_qualified_date_rent = sk_available_qualified_date_sale AND sk_available_qualified_date_sale>0 AND sk_available_qualified_date_rent>0 THEN 'Hybrid'
        WHEN sk_available_qualified_date_rent >0 AND sk_available_qualified_date_rent != sk_available_qualified_date_sale THEN 'Rent'
    END AS context_available_qualified_rent,
    CASE
        WHEN sk_opportunity_date_rent = sk_opportunity_date_sale AND sk_opportunity_date_sale>0 AND sk_opportunity_date_rent>0 THEN 'Hybrid'
        WHEN sk_opportunity_date_sale >0 AND sk_lead_date_rent != sk_opportunity_date_sale THEN 'Sale'
    END AS context_opportunity_sale,
    CASE
        WHEN sk_opportunity_date_rent = sk_opportunity_date_sale AND sk_opportunity_date_sale>0 AND sk_opportunity_date_rent>0 THEN 'Hybrid'
        WHEN sk_opportunity_date_rent >0 AND sk_opportunity_date_rent != sk_opportunity_date_sale THEN 'Rent'
    END AS context_opportunity_rent,
	llf.context_first_listing_sale,
	llf.context_first_listing_rent,
	llf.lead_discard_sale,
	llf.lead_discard_rent,
	llf.prospect_discard_sale,
	llf.prospect_discard_rent
FROM
    available_qualified llf