import pandas as pd

class Preprocessor():
    """
    preprocessing the dataframe (adding columns with steps of the process, filling values, removing lines that dont make sense)
    """

    def __init__(self, steps):
        self.steps = steps

    def preprocess(self, df):
        # regionless lines are assigned the region NONE
        df.loc[df.region_code.isnull(), 'region_code'] = 'NONE'
        df.loc[df.city_name.isnull(), 'city_name'] = 'NONE'

        # define steps of the process
        # df.loc[:, 'dt_booking_created_notrescheduled'] = df['dt_booking_created'].where(
        #     df.reason_category != 'Reschedule')  #
        df.loc[:, 'dt_effective_visit'] = df['dt_booking_scheduling'].where(
            df.visit_follow_up.isin(['VaiNegociar', 'Talvez', 'VisitouSozinho']))  # source ribaldo
        df.loc[:, 'dt_signature_notcancelled'] = df['dt_contract_signature'].where(
            df.contract_status.isin(['Ativo', 'Finalizado']))  # source ribaldo

        # remove duplicates
        df = df[~df.duplicated()]  # doesn't change the counts in past because we deduplicate there

        # replace null id booking by -1
        df.loc[:,'sk_booking'] = df['sk_booking'].fillna(-1) #nulls dont exist but who knows..

        # ordered_step_list = self.steps.index.tolist()
        # # business rules
        # for step in ordered_step_list[:-1]:
        #     row_step = self.steps.loc[step]
        #     deduplication_col_step = row_step.deduplication_col
        #
        #     step_index = ordered_step_list.index(step)
        #     next_step = ordered_step_list[step_index + 1]
        #     row_next_step = self.steps.loc[next_step]
        #     deduplication_next_step = row_next_step.deduplication_col
        #
        #     if deduplication_col_step != deduplication_next_step:
        #         print deduplication_col_step
        #         print deduplication_next_step
        #         print 'unique next_steps :'
        #         print df[deduplication_next_step].nunique()
        #         # if a key exist, its predecessor must also exist (not -1)
        #         df = df[((df[deduplication_col_step] ==-1) & (df[deduplication_next_step]==-1)) |
        #                 ((df[deduplication_col_step] != -1))]
        #         print 'no next steps appears out of nowhere. unique next steps :'
        #         print df[deduplication_next_step].nunique()
        #         # if a key is duplicated, its predecessor keys must be all equal
        #         c = None
        #         c = df[df[deduplication_next_step] != -1].groupby(deduplication_next_step).first()[deduplication_col_step] #correspondence between next step and step (eg what should the sk_booking be for a particular sk_offer)
        #         df = df[(df[deduplication_next_step]==-1) | (df[deduplication_col_step].values == c[df[deduplication_next_step]].values)]
        #         print 'same next step, same step. unique next_steps :'
        #         print df[deduplication_next_step].nunique()
        return df



