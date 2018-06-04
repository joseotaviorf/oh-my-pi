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
        df.loc[:, 'dt_booking_created_notrescheduled'] = df['dt_booking_created'].where(
            df.reason_category != 'Reschedule')  # source ribaldo
        df.loc[:, 'dt_effective_visit'] = df['dt_booking_scheduling'].where(
            df.visit_follow_up.isin(['VaiNegociar', 'Talvez', 'VisitouSozinho']))  # source ribaldo
        df.loc[:, 'dt_signature_notcancelled'] = df['dt_contract_signature'].where(
            df.contract_status.isin(['Ativo', 'Finalizado']))  # source ribaldo

        # remove duplicates
        df = df[~df.duplicated()]  # doesn't change the counts in past because we deduplicate there

        # replace null id booking by -1
        df.loc[:, 'sk_booking'] = df['sk_booking'].fillna(-1)  # nulls dont exist but who knows..

        return df
