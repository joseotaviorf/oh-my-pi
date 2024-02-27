SELECT 
    PersonalPaymentMethodId AS id_personal_payment_method,
    BankAccountId AS id_bank_account,
    PartyId AS id_party,
    OrgPaymentMethodId AS id_org_payment_method,
    PayrollRelationshipId AS id_payroll_relationship,    
    PersonNumber AS person_number,
    Name AS name,
    PaymentAmountType AS payment_amount_type,
    Amount AS amount,
    Percentage AS percentage,
    Priority AS priority,
    EffectiveStartDate AS dt_effective_start,
    EffectiveEndDate AS dt_effective_end,    
    ts_load
FROM datalake_hr_system_raw.personal_payment_methods