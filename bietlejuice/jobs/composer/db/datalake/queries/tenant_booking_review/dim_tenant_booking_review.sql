select
    b.id as sk_tenant_booking_review,
    b.id as id_tenant_booking_review,
    min(review.status) as review_status,
    max(case when array_contains(review.labels, '') then null else review.labels[1] end) as visit_not_happened_reason,
    cast(max(case when ftr.name='listingfidelity_v2' then array_join(rf.rating_selected, ',') else null end) as boolean) as is_listing_accurate,
    max(case when ftr.name='wronglistinginfo' then array_join(rf.rating_selected, ',') else null end) as wrong_listing_info,
    cast(max(case when ftr.name='offerintent' then array_join(rf.rating_selected, ',') else null end) as boolean) as is_offer_intent,
    max(case when ftr.name='noofferintentreason' then array_join(rf.rating_selected, ',') else null end) as no_offer_intent_reason,
    cast(max(case when ftr.name='painting' then array_join(rf.rating_selected, ',') else null end) as smallint) as painting,
    cast(max(case when ftr.name='costbenefit' then array_join(rf.rating_selected, ',') else null end) as smallint) as cost_benefit,
    cast(max(case when ftr.name='conservation' then array_join(rf.rating_selected, ',') else null end) as smallint) as conservation,
    cast(max(case when ftr.name='cleaning' then array_join(rf.rating_selected, ',') else null end) as smallint) as cleaning,
    cast(max(case when ftr.name='furniture' then array_join(rf.rating_selected, ',') else null end) as smallint) as furniture,
    cast(max(case when ftr.name='naturallight' then array_join(rf.rating_selected, ',') else null end) as smallint) as natural_light,
    cast(max(case when ftr.name='indoorsilence' then array_join(rf.rating_selected, ',') else null end) as smallint) as indoor_silence,
    cast(max(case when ftr.name='agentperformance' then array_join(rf.rating_selected, ',') else null end) as smallint) as agent_performance,
    cast(max(case when ftr.name='wantsameagent' then array_join(rf.rating_selected, ',') else null end) as boolean) as does_want_same_agent,
    max(case when ftr.name='visittype' then array_join(rf.rating_selected, ',') else null end) as visit_type,
    max(review.comment) as comment from datalake_insider_clean.review review
    join datalake_ebdb_clean.visit v on review.id_reviewed = v.code
    join datalake_ebdb_clean.booking b on b.id_visit = v.id
    left join datalake_insider_clean.review_feature rf on review.id = rf.id_review
    left join datalake_insider_clean.feature ftr on rf.id_feature = ftr.id
    where review.type='tenant_visit' 
    group by 1
