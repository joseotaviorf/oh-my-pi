drop view ebdb.vw_lead_reason;

create view ebdb.vw_lead_reason AS
select CONVERT('CONTACT_DIDNT_EXIST' USING utf8) as reason_detail, CONVERT('ContatoIncorreto' USING utf8) as reason
union all
select 'CONTACT_WAS_FROM_HOUSE_TENANT', 'ContatoIncorreto'
union all
select 'CONTACT_WAS_FROM_REAL_ESTATE_BROKER_OR_AGENT', 'ContatoIncorreto'
union all
select 'CONTACT_WAS_NO_LONGER_THE_HOUSE_OWNER', 'ContatoNaoValido'
union all
select 'CONTACT_WASNT_THE_HOUSE_OWNER', 'ContatoIncorreto'
union all
select 'DUPLICATED_LEAD', 'ImovelRepetido'
union all
select 'HOUSE_ALREADY_PUBLISHED', 'RepetidoPublicacao'
union all
select 'HOUSE_ALREADY_RENTED', 'ImovelOcupado'
union all
select 'HOUSE_ONLY_FOR_SELLING', 'ImovelParaVenda'
union all
select 'HOUSE_PRICE_WAS_OUT_OF_BOUNDS', 'ForaPreco'
union all
select 'HOUSE_UNDER_EXCLUSIVITY_CONTRACT', 'Exclusivo'
union all
select 'HOUSE_UNDER_RENOVATION', 'CasaReformando'
union all
select 'HOUSE_WAS_A_BUSINESS_REAL_ESTATE', 'TipoInvalido'
union all
select 'HOUSE_WAS_OUT_OF_APARTMENT_RENTING_REGIONS', 'ForaArea'
union all
select 'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS', 'ForaArea'
union all
select 'ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS', 'ProblemaEntrada'
union all
select 'OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH', 'ProprietarioRecusou'
union all
select 'OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_ACCEPT_ONLINE_PROCESS', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_ACCEPT_SELF_CONDO_PAYMENT_MODEL', 'ProprietarioRecusou'
union all
select 'OWNER_DIDNT_ANSWER_PHONE', 'ProprietarioNuncaAtende'
union all
select 'OWNER_DIDNT_LISTEN_TO_PITCH', 'ProprietarioNaoOuviuPitch'
union all
select 'OWNER_DIDNT_WANT_ADMINISTRATION', 'ProprietarioRecusou'
union all
select 'OWNER_EVALUATING', 'ProprietarioAvaliando'
union all
select 'OWNER_REQUESTING_ASSISTANCE', 'ProprietarioSolicitouAtendimento'
union all
select 'OWNER_WONT_ANSWER_PHONE', 'ProprietarioNaoAtende'