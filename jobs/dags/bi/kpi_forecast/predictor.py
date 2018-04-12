from ts_predictor import Ts_predictor
from funnel import Funnel
import pandas as pd
import matplotlib as plt
import numpy as np

class Predictor:
    """takes a preprocessed dataframe and stores it.

    the predict() method takes the parameters of the prediction (date begin and end)
    It will split the dataframe into past and future, and split the past into recent and training,
    then it will predict the first step and train a funnel
    finally it wil instruct the funnel to predict the remaining steps of the funnel
    """

    def __init__(self, df, steps, regions):
        self.df = df
        self.steps = steps
        self.regions = regions

        self.regions_def_params = {}

    def predict(self,
                begin_pred,
                end_pred,
                n_training_days=63,  # hard limit on the days we do not want to consider for creating distributions
                n_recent_days=21,
                rolavg_duration=120,
                min_samples=500,
                max_samples=5000000,
                model_weekly_seasonality=True,
                model_yearly_seasonality=True,
                ):

        self.begin_pred = begin_pred
        self.end_pred = end_pred
        self.range_pred_day = pd.date_range(begin_pred, end_pred, freq='D', closed='left')
        self.range_pred_week = pd.date_range(begin_pred, end_pred, freq='W-MON', closed='left')
        self.min_samples = min_samples
        self.max_samples = max_samples
        self.model_weekly_seasonality = model_weekly_seasonality
        self.model_yearly_seasonality = model_yearly_seasonality

        self.n_training_days = n_training_days
        self.n_recent_days = n_recent_days
        self.rolavg_duration = rolavg_duration

        self.range_recent_day = pd.date_range(self.begin_pred - pd.to_timedelta(self.n_recent_days, unit='days'),
                                              self.begin_pred,
                                              freq='D',
                                              closed='left')
        self.range_training_day = pd.date_range(self.begin_pred - pd.to_timedelta(self.n_training_days, unit='days'),
                                                self.begin_pred,
                                                freq='D',
                                                closed='left')

        # split df into past and future
        self.past_df = self.df[(self.df[self.steps.index[0]] < self.begin_pred)].copy()  # todo : copy needed?
        self.future_df = self.df[(self.df[self.steps.index[
            0]] >= self.begin_pred)].copy()  # should be empty in production or just contain the data of this week

        self.kpi_pred = pd.DataFrame()  # dataframe to be filled with predictions from regions

        # for each combination of city, region : make predictions for bookings and for rest of funnel.
        # sort regions by number of lines, so we will always handle big geographies first and have default parameters available
        self.regions = self.regions.sort_index(level=['city', 'region'],
                                               ascending=[False, False])  # 'all' should be first
        for (city, region), row in self.regions.iterrows():
            print city + ' ' + region
            if city == 'NONE' or region == 'NONE':
                continue

            # filter the dataframe to keep only regional events
            if city == 'all':
                df_regional = self.past_df.copy()
            elif region == 'all':
                df_regional = self.past_df[self.past_df.city_name == city]
            else:  # city is not all and region is not all and is not NONE
                df_regional = self.past_df[self.past_df.region_code == region]

            if df_regional.shape[0] == 0:
                print 'skipping region because there is no data for it'
                continue  # we don't try to predict and don't store anything if the regional df is empty
                regional_yearly_seasonality = None
                regional_distribs = None

            # define fallback parameters
            else:  # there is regional data
                if city == 'all':
                    default_yearly_seasonality = None
                    default_distribs = None
                elif region == 'all':
                    default_yearly_seasonality = self.regions_def_params['all']['all'][
                        'yearly_seasonality']  # self.regions.loc[('all', 'all'),'yearly_seasonality']
                    default_distribs = self.regions_def_params['all']['all'][
                        'distribs']  # self.regions.loc[('all', 'all'),'distribs']
                    print 'using overall yearly seasonality and distribs as defaults'
                else:  # city is not all and region is not all and is not NONE
                    default_yearly_seasonality = self.regions_def_params[city]['all']['yearly_seasonality']
                    default_distribs = self.regions_def_params[city]['all']['distribs']
                    print 'using city yearly seasonality and distribs as defaults'
                    if default_yearly_seasonality is None:
                        default_yearly_seasonality = self.regions_def_params['all']['all'][
                            'yearly_seasonality']  # self.regions.loc[('all', 'all'),'yearly_seasonality']
                        print 'could not use city seasonality : using overall yearly seasonality as defaults'
                    if default_distribs is None:
                        default_distribs = self.regions_def_params['all']['all'][
                            'distribs']  # self.regions.loc[('all', 'all'),'distribs']
                        print 'could not use city distibs : using overall distribs as defaults'

                ### actual prediction here :)
                regional_kpi_pred, regional_yearly_seasonality, regional_distribs = self.__predict_single_geography(
                    df_regional,
                    default_yearly_seasonality,
                    default_distribs)  # dataframe with index = range_pred_day
                if regional_kpi_pred is not None:
                    # concatenate the regional_kpi_pred in the overall prediction dataframe
                    regional_kpi_pred['city'] = city
                    regional_kpi_pred['region'] = region
                    regional_kpi_pred = regional_kpi_pred.set_index(['city', 'region'], append=True)
                    self.kpi_pred = pd.concat([self.kpi_pred, regional_kpi_pred], axis=0)  # add the regional prediction under the existing df

            # store the regional parameters
            if city not in self.regions_def_params.keys():
                self.regions_def_params[city] = {}
            if region not in self.regions_def_params[city].keys():
                self.regions_def_params[city][region] = {}
            self.regions_def_params[city][region]['yearly_seasonality'] = regional_yearly_seasonality
            self.regions_def_params[city][region]['distribs'] = regional_distribs

        self.kpi_pred = self.kpi_pred.reorder_levels([1, 2, 0])

        return self.kpi_pred

    def __predict_single_geography(self, df, default_yearly_seasonality, default_distribs):
        """
        receives as input the preprocessed dataframe of events of a single geography. this dataframe contains
        only events with booking dates prior to begin_pred.
        outputs the dataframe of predicted kpis
        """

        ### Predict bookings
        ts_first_step = self.get_count(df, self.steps.index[
            0])  # contains first step regions that have data in the past #defined over beginning-begin_pred -1
        predictor = Ts_predictor(ts_first_step,
                                 self.begin_pred,
                                 self.end_pred,
                                 self.range_pred_day,
                                 self.range_pred_week,
                                 )
        ts_first_step_pred = predictor.predict(
            model_weekly_seasonality=self.model_weekly_seasonality,
            model_yearly_seasonality=self.model_yearly_seasonality,
            default_yearly_seasonality=default_yearly_seasonality,
            rolavg_duration=self.rolavg_duration,
        )  # defined over range_pred_day

        if ts_first_step_pred is None:  # prediction failed
            print 'prediction failed'
            return [None, None, None]
        # todo : add default yearly seasonality #contains first step of regions that were predicted #defined over range_pred_day

        ### Predict rest of the funnel
        train_df, recent_df = self.split_data(df, self.n_training_days, self.n_recent_days)
        # print train_df.head()
        geo_funnel = Funnel(self.steps,  # deduplication_col	order	predict_with	step	q_threshold
                            train_df,
                            # we pass the past as a parameter to be sure not to give any info about the future away
                            begin_pred=self.begin_pred,
                            end_pred=self.end_pred,
                            range_recent_day=self.range_recent_day,
                            range_pred_day=self.range_pred_day,
                            default_distribs=default_distribs,
                            min_samples=self.min_samples,
                            max_samples=self.max_samples,
                            )  # init computes the thresholds and the distribs
        # demand_funnel.display_step_thresholds()

        regional_kpi_pred = geo_funnel.predict(recent_df, ts_first_step_pred)

        # return the prediction and the yearly seasonality and distributions for this geography
        return [regional_kpi_pred, predictor.own_yearly_seasonality, geo_funnel.distribs]

    def split_data(self,
                   df,
                   n_training_days=63,  # hard limit on the days we do not want to consider for creating distributions
                   n_recent_days=21):
        """we set a limit between training data (all bookings older than a threshold date,
        for which we are sure the process is finished) and current data (other bookings)"""

        # todo : we can probably reduce the period of the recent set as we are limited by the maximum delay between two consecutive steps, not the delay between booking and contract
        # todo : check if we need the copy()
        train_df = df[
            df[self.steps.index[0]] >= (self.begin_pred - pd.to_timedelta(n_training_days, unit='days'))].copy()
        recent_df = df[
            df[self.steps.index[0]] >= (self.begin_pred - pd.to_timedelta(n_recent_days, unit='days'))].copy()

        return [train_df, recent_df]

    def get_count(self, df, step):
        """returns a series with the number of steps on each day. days with no steps are not included"""

        deduplication_col_step = self.steps.loc[step, 'deduplication_col']
        df_dedup = df.drop_duplicates(deduplication_col_step)  # returns a copy

        daily = df_dedup.groupby(df_dedup[step].dt.date).count().iloc[:, 0]
        daily.index = pd.DatetimeIndex(daily.index).rename('index')
        daily = daily.rename(step)

        return daily  # return a series

    def get_all_counts(self, df):
        all_counts = pd.DataFrame
        for step in self.steps.index().tolist():
            all_counts = pd.concat([all_counts, self.get_count(df, step)], axis=1)

        return all_counts

    def accuracy(self, daily_future, daily_pred, begin=0, end=1, av=True):
        weekly_future = self.daily_to_weekly(daily_future)[begin:end]
        weekly_pred = self.daily_to_weekly(daily_pred)[begin:end]

        if av == True:
            return np.abs(
                1 - weekly_pred / weekly_future).mean()  # average of absolute deviation on the week in percentage of real value
        else:
            return (1 - weekly_pred / weekly_future).mean()

    def print_funnels(self, kpis):
        """calls print_ts for every step of the funnel, and does one figure per region"""
        range_display_past = pd.date_range(self.begin_pred - pd.to_timedelta(180, unit='days'),
                                           self.begin_pred,
                                           freq='D',
                                           closed='left')

        # for every distinct combinatin of city and region that was predicted
        for (city, region), row in self.kpi_pred.reset_index()[['city', 'region']].drop_duplicates().set_index(
                ['city', 'region']).iterrows():
            fig = plt.figure(figsize=(10, 10))
            ax = fig.add_subplot(111)
            ax.set_title(city + ' ' + region)

            for print_step in self.steps.index:
                daily_past = kpis.loc[(city, region, range_display_past.tolist()), print_step].reset_index(
                    level=['city', 'region'], drop=True)
                daily_pred = self.kpi_pred.loc[(city, region, self.range_pred_day.tolist()), print_step].reset_index(
                    level=['city', 'region'], drop=True)

                try:
                    daily_future = kpis.loc[(city, region, self.range_pred_day.tolist()), print_step].reset_index(
                        level=['city', 'region'], drop=True)
                except KeyError:  # there is a keyerror, meaning that this region does not have values in the future
                    print 'keyerror ' + city
                    self.print_ts_weekly(ax, daily_past, daily_pred, None, label=region + '_' + print_step)
                else:
                    self.print_ts_weekly(ax, daily_past, daily_pred, daily_future, label=region + '_' + print_step)

            # matplotlib
            ax.set_xlim(left=range_display_past.min(), right=self.end_pred)

            ax.axvline(pd.to_datetime('1/1/2018'), ls=':')
            ax.axvline(pd.to_datetime('1/1/2017'), ls=':')
            ax.axvline(pd.to_datetime('1/1/2016'), ls=':')
            ax.axvline(pd.to_datetime('1/1/2015'), ls=':')
            ax.axvline(self.begin_pred, ls='--')
            ax.axvline(daily_future.index[-1], ls='--')
            ax.axvline(self.end_pred, ls='--')

            ax.set_xlabel("date of booking")
            ax.set_ylabel("weekly bookings")

            fig.show()

    def print_ts(self, ax, ts_past, ts_pred, ts_future, label=None):  # ,kind='bar' #, color=None
        if ts_future is not None:
            # don't display the last observation (day, week) of ts_future because it is incomplete
            ts_future = ts_future.iloc[:-1]

        if ts_past is not None and ts_future is not None:
            ts_true = pd.concat([ts_past, ts_future])
        elif ts_past is not None:
            ts_true = ts_past
        elif ts_future is not None:
            ts_true = ts_future

        # to have a continuous line between past and pred, add the last datapoint of past to the pred series
        if ts_pred is not None and ts_past is not None:
            ts_pred = ts_past.iloc[-1:].append(ts_pred)

        color_pred = 'r'
        color_true = 'g'

        # lines :
        if ts_true is not None:
            ax.plot(ts_true, label=label + ' actual', color=color_true, alpha=0.4, ls='-')
        if ts_pred is not None:
            ax.plot(ts_pred, label=label + ' prediction', color=color_pred, alpha=0.7, lw=0.5)

        # fill between:
        if ts_pred is not None and ts_future is not None:
            ax.fill_between(ts_future.index, ts_pred[ts_future.index], ts_future, color='k', alpha=0.2)

        if label is not None:
            ax.annotate(label + '_prediction',
                        xy=(ts_pred.index[-1], ts_pred[-1]),
                        xytext=(ts_pred.index[-1] + pd.to_timedelta(7, unit='days'), ts_pred[-1]),
                        arrowprops=dict(facecolor='black', shrink=0.05)
                        )
            ax.annotate(label + '_actual',
                        xy=(ts_true.index[-1], ts_true[-1]),
                        xytext=(ts_true.index[-1] + pd.to_timedelta(7, unit='days'), ts_true[-1]),
                        arrowprops=dict(facecolor='black', shrink=0.05)
                        )

    def daily_to_weekly(self, ts):
        return ts.resample('W-MON', closed='left', label='left').sum()

    def print_ts_weekly(self, ax, daily_past, daily_pred, daily_future=None, label=None):
        """wrapper to print_ts function to convert to weekly data"""
        weekly_past = None
        weekly_pred = None
        weekly_future = None

        if daily_past is not None:
            weekly_past = self.daily_to_weekly(daily_past)
        if daily_pred is not None:
            weekly_pred = self.daily_to_weekly(daily_pred)
        if daily_future is not None:
            weekly_future = self.daily_to_weekly(daily_future)

        self.print_ts(ax, weekly_past, weekly_pred, weekly_future, label=label)