import pandas as pd

class Preprocessor():
    """for the demand funnel, provides 3 methods:
    - preprocessing the dataframe (adding columns with steps of the process, filling values)
    - computing the number of occurences of each step for each day
    - get a list of regions
    """

    def __init__(self, steps):
        self.steps = steps

    def preprocess(self, df):
        # regionless lines are assigned the region NONE
        df.loc[df.region_code.isnull(), 'region_code'] = 'NONE'
        df.loc[df.city_name.isnull(), 'city_name'] = 'NONE'

        # define steps of the process
        df.loc[:, 'dt_booking_created_notrescheduled'] = df['dt_booking_created'].where(
            df.reason_category != 'Reschedule')  #
        df.loc[:, 'dt_effective_visit'] = df['dt_booking_scheduling'].where(
            df.visit_follow_up.isin(['VaiNegociar', 'Talvez', 'VisitouSozinho']))  # source ribaldo
        df.loc[:, 'dt_signature_notcancelled'] = df['dt_contract_signature'].where(
            df.contract_status.isin(['Ativo', 'Finalizado']))  # source ribaldo

        # remove duplicates
        df = df[~df.duplicated()]  # doesn't change the counts in past because we deduplicate there

        # replace null id booking by -1
        df.loc[:,'id_booking'] = df['id_booking'].fillna(-1)

        ordered_step_list = self.steps.index.tolist()
        # business rules
        for step in ordered_step_list[:-1]:
            row_step = self.steps.loc[step]
            deduplication_col_step = row_step.deduplication_col

            step_index = ordered_step_list.index(step)
            next_step = ordered_step_list[step_index + 1]
            row_next_step = self.steps.loc[next_step]
            deduplication_next_step = row_next_step.deduplication_col

            if deduplication_col_step != deduplication_next_step:
                print deduplication_col_step
                print deduplication_next_step
                print 'unique next_steps :'
                print df[deduplication_next_step].nunique()
                # if a key exist, its predecessor must also exist (not -1)
                df = df[((df[deduplication_col_step] ==-1) & (df[deduplication_next_step]==-1)) |
                        ((df[deduplication_col_step] != -1))]
                print 'no next steps appears out of nowhere. unique next steps :'
                print df[deduplication_next_step].nunique()
                # if a key is duplicated, its predecessor keys must be all equal
                c = None
                c = df[df[deduplication_next_step] != -1].groupby(deduplication_next_step).first()[deduplication_col_step] #correspondence between next step and step (eg what should the sk_booking be for a particular sk_offer)
                df = df[(df[deduplication_next_step]==-1) | (df[deduplication_col_step].values == c[df[deduplication_next_step]].values)]
                print 'same next step, same step. unique next_steps :'
                print df[deduplication_next_step].nunique()
            x=1
        return df

    def get_regions(self, df):
        # individual regions
        regions = df.groupby(['city_name', 'region_code']).size().reset_index()
        regions.columns = ['city', 'region', 'cnt']

        # cities
        cities = df.groupby(['city_name']).size().reset_index()
        cities.columns = ['city', 'cnt']
        cities['region'] = 'all'
        cities = cities[['city', 'region', 'cnt']]
        regions = pd.concat([regions, cities])

        # all of quintoandar
        regions = regions.append({'city': 'all',
                                  'region': 'all',
                                  'cnt': df.shape[0]}, ignore_index=True)

        # regions = regions.sort_values('cnt', ascending=False)
        regions = regions.set_index(['city', 'region'])
        return regions

    def get_kpis(self, df, regions):
        # we count as an instance of a step a row that remains after a deduplication by the key of that step
        past = None
        for step, row_step in self.steps.iterrows():
            s_step = pd.DataFrame()
            for (city, region), row in regions.iterrows():
                if city == 'all':
                    df_region = df.copy()
                elif region == 'all':
                    df_region = df[df.city_name == city]
                else:
                    df_region = df[df.region_code == region]
                t = df_region.drop_duplicates(row_step.deduplication_col)
                s = t.groupby(pd.to_datetime(t[step].dt.date)).size()
                s = pd.DataFrame(s, columns=[step])
                s.index = pd.MultiIndex.from_product([[city], [region], s.index],
                                                     names=['city', 'region', 'date'])
                s_step = pd.concat([s_step, s], axis=0)  # we put all regions together in a big column

            if past is None:
                past = s_step
            else:
                past = past.merge(s_step, how='outer', left_index=True, right_index=True).fillna(0.0)

        past.columns = self.steps.index.tolist()
        return past


def test1():
    pass

if __name__ == "__main__":
    test1()



