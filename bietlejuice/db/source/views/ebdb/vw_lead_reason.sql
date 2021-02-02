drop view ebdb.vw_lead_reason;

create view ebdb.vw_lead_reason AS
select CONVERT('CONTACT_ON_BLOCK_LIST' USING utf8) as reason_detail, CONVERT('Blocklist' USING utf8) as reason
union all
select 'OWNER_DIDNT_WANT_RECEIVE_CALL', 'Blocklist'
union all
select 'CONTACT_KNOW_OWNER', 'Contato'
union all
select 'CONTACT_WASNT_THE_HOUSE_OWNER', 'Contato'
union all
select 'CONTACT_DIDNT_EXIST', 'Contato'
union all
select 'OWNER_DIDNT_ANSWER_PHONE', 'Contato'
union all
select 'SEASONAL_RENT', 'ForaDoModelo'
union all
select 'HOUSE_ONLY_FOR_SELLING', 'ForaDoModelo'
union all
select 'ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING', 'ForaDoModelo'
union all
select 'HOUSE_WITH_BAD_CONDITIONS', 'ForaDoModelo'
union all
select 'HOUSE_WAS_A_BUSINESS_REAL_ESTATE', 'ForaDoModelo'
union all
select 'HOUSE_PRICE_WAS_OUT_OF_BOUNDS', 'ForaDoModelo'
union all
select 'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS', 'ForaDoModelo'
union all
select 'HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS', 'ForaDoModelo'
union all
select 'ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS', 'ImovelIndisponivel'
union all
select 'ISSUES_WITH_HOUSE_DOCUMENTATION', 'ImovelIndisponivel'
union all
select 'HOUSE_UNDER_MAJOR_RENOVATION', 'ImovelIndisponivel'
union all
select 'HOUSE_ALREADY_RENTED', 'ImovelIndisponivel'
union all
select 'HOUSE_ALREADY_SOLD', 'ImovelIndisponivel'
union all
select 'PROPERTY_IN_OFFPLANT', 'ImovelIndisponivel'
union all
select 'PROPERTY_IN_JUDICIAL_INVENTORY', 'ImovelIndisponivel'
union all
select 'HOUSE_ALREADY_PUBLISHED', 'Duplicado'
union all
select 'DUPLICATED_LEAD', 'Duplicado'
union all
select 'OWNER_GAVE_UP_SELLING', 'ProprietarioRecusou'
union all
select 'OWNER_DISAGREE_PAYMENT_TIMING', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_SELECT_CONTEXT', 'ProprietarioRecusou'
union all
select 'OWNER_CONSIDERED_SALE_FEE_TOO_HIGH', 'ProprietarioRecusou'
union all
select 'HOUSE_UNDER_EXCLUSIVITY_CONTRACT', 'ProprietarioRecusou'
union all
select 'OWNER_WITH_PRIME_PROFILE', 'ProprietarioRecusou'
union all
select 'OWNER_GAVE_UP_RENTING', 'ProprietarioRecusou'
union all
select 'OWNER_DISAGREE_CHARGES_PAYMENTS', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_WANT_ADMINISTRATION', 'ProprietarioRecusou'
union all
select 'OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH', 'ProprietarioRecusou'
union all
select 'OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_LISTEN_TO_PITCH', 'ProprietarioRecusou'
union all
select 'HOUSE_UNDER_RENOVATION', 'EmProspeccao'
union all
select 'OWNER_WONT_ANSWER_PHONE', 'EmProspeccao'
union all
select 'OWNER_EVALUATING', 'EmProspeccao'
union all
select 'OWNER_FINISHING_SELFSERVICE', 'EmProspeccao'
union all
select 'OWNER_UNAVAILABLE', 'EmProspeccao'
union all
select 'OWNER_NEED_SCHEDULE_PHOTOS', 'EmProspeccao'
union all
select 'ProprietarioVaiAnunciar', 'Deprecated'
union all
select 'CONTACT_WAS_FROM_HOUSE_TENANT','Deprecated'
union all
select 'CONTACT_WAS_FROM_REAL_ESTATE_BROKER_OR_AGENT', 'Deprecated'
union all
select 'HOUSE_WAS_OUT_OF_APARTMENT_RENTING_REGIONS', 'Deprecated'
union all
select 'CONTACT_WAS_NO_LONGER_THE_HOUSE_OWNER', 'Deprecated'
union all
select 'OWNER_DIDNT_ACCEPT_ONLINE_PROCESS', 'Deprecated'
union all
select 'OWNER_REQUESTING_ASSISTANCE', 'Deprecated'
union all
select 'OWNER_DIDNT_ACCEPT_SELF_CONDO_PAYMENT_MODEL', 'Deprecated'
