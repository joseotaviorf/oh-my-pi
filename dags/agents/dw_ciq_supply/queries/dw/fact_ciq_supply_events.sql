SELECT
    MD5(CONCAT(COALESCE(supp.id_supply_lead, -1), 
               COALESCE(supp.supply_source, 'empty'), 
               COALESCE(supp.id_house,-1),
               supp.business_context,
               supp.id_funnel_step)
    ) AS sk_ciq_supply_event,
    supp.id_supply_lead AS sk_supply_lead,
    supp.id_supply_source AS sk_supply_source,
    supp.id_owner AS sk_owner,
    supp.id_house AS sk_house,
    supp.id_user_affiliate AS sk_user_affiliate,
    supp.id_user_registrant AS sk_user_registrant,
    supp.id_user_conversion AS sk_user_conversion,
    supp.id_funnel_step AS sk_funnel_step,    
    CASE
      WHEN supp.business_context = 'RENT' THEN TRUE
      ELSE FALSE
    END AS is_for_rent,
    CASE
      WHEN supp.business_context = 'SALE' THEN TRUE
      ELSE FALSE
    END AS is_for_sale,  
    CASE
      WHEN supp.origin = 'ciq' THEN TRUE
      ELSE FALSE
    END AS is_ciq,
    CASE
      WHEN supp.origin = 'operations' AND (supp.application IN ('admin_confirmation','portfolio_manager','consultantpwa') OR supp.ops_agent = 'ciq') THEN TRUE
      ELSE FALSE
    END AS is_ciq_operations,
    supp.ts_event,
    NOW() AS ts_load
FROM
    datalake_ciq.ciq_supply_events_tracking AS supp 