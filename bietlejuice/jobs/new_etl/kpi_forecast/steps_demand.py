import pandas as pd
steps = pd.DataFrame([{'step': 'dt_booking_created',
                       'deduplication_col': 'sk_booking',
                       'order': 1,
                       'predict_with': None},

                      {'step': 'dt_booking_created_notrescheduled',
                       'deduplication_col': 'sk_booking',
                       'order': 2,
                       'predict_with': 'dt_booking_created'},

                      {'step': 'dt_effective_visit',
                       'deduplication_col': 'sk_booking',
                       'order': 3,
                       'predict_with': 'dt_booking_created_notrescheduled'},
                      # only not rescheduled bookings can create an effective visit

                      {'step': 'dt_offer_first_sent',
                       'deduplication_col': 'sk_offer',
                       'order': 4,
                       'predict_with': 'dt_booking_created'},
                      # any booking, rescheduled or not, effectlively visited or not, can create an offer

                      {'step': 'dt_offer_approved',
                       'deduplication_col': 'sk_offer',
                       'order': 5,
                       'predict_with': 'dt_offer_first_sent'},

                      {'step': 'dt_tenant_first_document_sent',
                       'deduplication_col': 'sk_proposal',
                       'order': 6,
                       'predict_with': 'dt_offer_approved'},

                      {'step': 'dt_credit_analysis_init',
                       'deduplication_col': 'sk_proposal',
                       'order': 7,
                       'predict_with': 'dt_tenant_first_document_sent'},

                      {'step': 'dt_proposal_approved',
                       'deduplication_col': 'sk_proposal',
                       'order': 8,
                       'predict_with': 'dt_offer_approved'},  #

                      {'step': 'dt_signature_notcancelled',
                       'deduplication_col': 'sk_contract',
                       'order': 9,
                       'predict_with': 'dt_proposal_approved'},
                      ])

steps = steps.set_index('step')
