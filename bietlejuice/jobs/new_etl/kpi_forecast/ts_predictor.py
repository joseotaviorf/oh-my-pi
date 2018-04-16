import pandas as pd
from collections import deque
import matplotlib as plt
from statsmodels.tsa.arima_model import ARIMA
import numpy as np


class Ts_predictor:
    """Takes a time series, looks at it until begin_pred-1 included,
    and predicts its future between begin_pred and end_pred

    Attributes:
      ts: a series (time series) with the counts as values.
      the index must not necessarily be a datetimeindex, but should be able to be converted to it.
      if every day is not in the index (gaps), they will be filled with 0

      begin_pred : first day of predictions included

      end_pred : last day of predictions included
    """

    def __init__(self,
                 ts,
                 begin_pred,
                 end_pred,
                 range_pred_day,
                 range_pred_week,
                 ):
        """we store arguments and we modify the timeseries (fill gaps and cut)"""

        # we store arguments
        self.begin_pred = begin_pred
        self.end_pred = end_pred
        self.range_pred_day = range_pred_day
        self.range_pred_week = range_pred_week
        self.daily_past = ts
        self.own_yearly_seasonality = None

        # transform the series into a series with a datetime index
        self.daily_past.index = pd.DatetimeIndex(self.daily_past.index)

        # make sure there are no gaps: (for things like rolling std that are based on int not days)
        self.begin_ts = pd.to_datetime(self.daily_past.index.min())
        self.end_ts = self.begin_pred - pd.to_timedelta(1, unit='days')  # pd.to_datetime(self.daily_past.index.max())
        self.daily_past = pd.concat(
            [pd.DataFrame(index=pd.date_range(self.begin_ts, self.end_ts, freq='D', closed=None)),
             self.daily_past],
            axis=1).fillna(0.0).iloc[:, 0]

        # cut the end of the series : make sure to cut the series before begin_pred
        # cut the beginning of the series :
        ##find the last date at which the bookings were null for one week.
        ##the end of that week is the beginning of the period we consider to make predictions
        ##if this date does not exit, we do not need to cut the series
        rolling_daily = self.daily_past.rolling(7).sum()
        begin_ts_candidate = pd.to_datetime(rolling_daily[rolling_daily == 0].index.max())
        if pd.notnull(begin_ts_candidate): self.begin_ts = begin_ts_candidate
        # self.end_ts = min(self.end_ts, self.begin_pred-pd.to_timedelta(1,unit='days'))
        self.daily_past = self.daily_past.loc[pd.date_range(self.begin_ts, self.end_ts, freq='D', closed=None)]

    def daily_to_weekly(self, ts):
        return ts.resample('W-MON', closed='left', label='left').sum()

    def rolling_mean_until_yesterday(self, s, days=7):
        if days > 0:
            return (s.rolling(days + 1).sum() - s) / float(days)
        if days == 0:
            return s
        else:
            return -1

    def add_one_do(self, ts):
        ts = ts + 1  # we will remove 1 booking at the end. we avoid having infinite values after taking the log of 0[]
        return ts

    def add_one_undo(self, ts):
        # remove 1 (1 was added in the beginning to avoid taking the log of 0)
        ts = ts - 1
        ts.loc[ts < 0] = 0
        return ts

    def log_do(self, ts):
        ts = np.log(ts)
        return ts

    def log_undo(self, ts):
        ts = np.exp(ts)
        return ts

    def remove_weekly_seasonality_do(self, ts):
        # find the weekly seasonality: dailylog/dailylog7drollingavg, groupby weekday/sum
        rolavg7_ts = self.rolling_mean_until_yesterday(ts,
                                                       days=7)  # for each day the average of the last 7 days, not including this day
        ratio7_ts = ts / rolavg7_ts  # should be close to 1 on average

        # todo : remove specific step:
        ratio7_ts_2y_positive = ratio7_ts.loc[
            (ratio7_ts.index >= pd.Timestamp('1/1/2016')) & (ratio7_ts.index < self.begin_pred) & (
            ratio7_ts > 0).values]

        self.weekly_seasonality = ratio7_ts_2y_positive.groupby(
            ratio7_ts_2y_positive.index.to_series().dt.weekday).mean()  # should be close to 1 on average
        self.weekly_seasonality = self.weekly_seasonality / self.weekly_seasonality.sum() * 7  # the sum of a normal week should be 7, not 7.02
        if self.weekly_seasonality[self.weekly_seasonality.notnull()].shape[0] < 7:
            print 'Not enough data to compute weekly seasonality'
            return None

        # correct all the days by their weekly seasonality. if 80% of normal, divide by 0.8 (hypothesis weekly and yearly seasonality are independent)
        seasonality_factor_week = self.weekly_seasonality.loc[ts.index.to_series().dt.weekday]  ###new
        seasonality_factor_week.index = ts.index
        ts_no7dseasonality = ts.divide(seasonality_factor_week)
        return ts_no7dseasonality

    def remove_weekly_seasonality_undo(self, ts):  # the series we want to add the seasonality to
        seasonality_factor_week_pred = self.weekly_seasonality[self.range_pred_day.to_series().dt.weekday]
        seasonality_factor_week_pred.index = self.range_pred_day
        ts_withweeklyseasonality = seasonality_factor_week_pred * ts
        return ts_withweeklyseasonality

    def remove_yearly_seasonality_do(self, ts, rolavg_duration=120):
        # find the yearly seasonality (based on last 2 years, with centered rolling mean)
        self.rolavg_ts = ts.rolling(rolavg_duration, center=True).mean()
        ratio_ts = ts / self.rolavg_ts  # should be close to 1 on average, but isnt
        # - shift of (one year*2/3 + 2 years*1/3) to remove the seasonality within the year
        ys = pd.DataFrame(ratio_ts)
        ys = ys[ys.index > pd.to_datetime('2016-01-01')]  # ignore turbulent years
        ys['datemonth'] = pd.to_datetime((2016 * 10000 + ys.index.to_series().dt.month * 100 + ys.index.to_series().dt.day).astype(str))
        ys = ys[ys.iloc[:, 0].notnull()]
        ysm = ys.groupby('datemonth').mean().iloc[:, 0]
        self.yearly_seasonality = ysm.rolling(7, min_periods=1, center=True).mean()
        self.yearly_seasonality.index = self.yearly_seasonality.index.to_series().dt.strftime('%m-%d')

        #     ### always use the default (test)
        #     if self.default_yearly_seasonality is not None :
        #       print 'always using the default because it exists.'
        #       self.yearly_seasonality = self.default_yearly_seasonality

        # remove the yearly seasonality
        seasonality_factor_year = self.yearly_seasonality[ts.index.to_series().dt.strftime('%m-%d')].ffill(
            limit=3).bfill(limit=3)  # we allow a limited number of missing values
        seasonality_factor_year.index = ts.index
        ts_noYseasonality = ts.divide(seasonality_factor_year)

        # check if the last three weeks + rolavg_duration before begin_pred are part of the series.
        # if not, it means we didn't have enough data to compute it
        # todo : if not, use the overall yearly seasonality
        if not set(pd.date_range(self.begin_pred - pd.to_timedelta(22 + rolavg_duration, unit='days'),
                                 self.begin_pred - pd.to_timedelta(1, unit='days'),
                                 freq='D', closed=None)).issubset(set(ts_noYseasonality[ts_noYseasonality.notnull()].index)):
            if self.default_yearly_seasonality is not None:
                print 'not enough data to compute the yearly seasonality of region. Computing using the default.'
                self.yearly_seasonality = self.default_yearly_seasonality
                self.own_yearly_seasonality = None
                # remove the yearly seasonality (repeating a few lines from above)
                seasonality_factor_year = self.yearly_seasonality[ts.index.to_series().dt.strftime('%m-%d')].ffill(
                    limit=3).bfill(limit=3)  # we allow a limited number of missing values
                seasonality_factor_year.index = ts.index
                ts_noYseasonality = ts.divide(seasonality_factor_year)
            else:
                print 'not enough data to compute the yearly seasonality of region and no default. Computing without'
                self.model_yearly_seasonality = False
                ts_noYseasonality = ts
        else:
            self.own_yearly_seasonality = self.yearly_seasonality
        return ts_noYseasonality

    def remove_yearly_seasonality_undo(self, ts):  # series we want to add the yearly seasonality to
        if self.model_yearly_seasonality == True:
            # add back the yearly seasonality
            seasonality_factor_year_pred = self.yearly_seasonality[self.range_pred_day.to_series().dt.strftime('%m-%d')]
            seasonality_factor_year_pred.index = self.range_pred_day
            ts_withYseasonality = seasonality_factor_year_pred * ts

            return ts_withYseasonality
        else:
            return ts

    def remove_trend_do(self, ts, rolavg_duration=120):  # series you want to remove the trend from
        # compute rolling avg without yearly seasonality, remove it to make the series stationary
        rolavg_ts = self.rolling_mean_until_yesterday(ts, days=rolavg_duration)
        # if the last three weeks (model for prediction based on 3 weeks) are not part of the rolling average timeseries, it means there was not enough data to compute it
        if not set(pd.date_range(self.begin_pred - pd.to_timedelta(22, unit='days'),
                                 self.begin_pred - pd.to_timedelta(1, unit='days'),
                                 freq='D', closed=None)).issubset(set(rolavg_ts[rolavg_ts.notnull()].index)):
            print 'not enough data to make the region stationary.'
            return None
        ts_notrend = ts - rolavg_ts
        return ts_notrend

    def remove_trend_undo(self,
                          notrend_ts_pred,  # - the time series we want to add the rolling average to
                          result_last_do,  # -the series for the past, with its trend
                          rolavg_duration=120):
        # for every day that we want to predict, take the predicted "notrend" value and add the rolling average 120 until the day before
        ts_pred = result_last_do.copy()
        for d in self.range_pred_day:
            rolavg_ts_pred_d = ts_pred[
                pd.date_range(d - pd.to_timedelta(rolavg_duration, unit='d'), d - pd.to_timedelta(1, unit='d'))].mean()
            ts_pred[d] = notrend_ts_pred[d] + rolavg_ts_pred_d  # [d]

        return ts_pred[self.range_pred_day]

    def predict_stationary_series_by_week(self, ts):
        # group the remaining TS by week
        ##keep only notnull
        ts = ts[pd.notnull(ts)]
        weekly_ts = ts.resample('W-MON', closed='left', label='left').sum()

        ##########modeling
        # create model based on last 3 weeks (this data does not contain yearly patterns) to predict the next one
        ts = weekly_ts
        model = ARIMA(ts, order=(3, 0, 0))
        try:
            results_AR = model.fit(disp=-1)
        except np.linalg.linalg.LinAlgError:
            print 'fit did not converge'
            return None
        else:
            ts_pred = model.predict(results_AR.params, start=self.begin_pred, end=self.end_pred, dynamic=False)
            weekly_ts_pred = pd.Series(ts_pred, index=self.range_pred_week)
            # when a week is predicted, split its size in 7 equal days
            ts_pred = weekly_ts_pred.resample('D').ffill()[self.range_pred_day].ffill() / 7
            return ts_pred

    def plot_ts(self, ts, ax=None, title='', std=False):

        if std is True:
            ts = pd.rolling_std(ts, window=30)

        if ax is None:
            fig = plt.figure(figsize=(10, 5))
            ax = fig.add_subplot(111)
            ax.set_title(title)

            ax.plot(ts.index, ts)

            ax.legend()
            fig.show()

    def predict(self,
                ax=None,
                ax_log=None,
                ax_notrend=None,
                model_weekly_seasonality=True,
                model_yearly_seasonality=True,
                default_yearly_seasonality=None,
                plot=False,
                rolavg_duration=90,
                ):

        """returns the prediction over range_pred_day"""
        # note: variables ending in _pred are defined over range_pred_day

        do_queue = deque()  # [] #append, popleft
        undo_stack = []  # append, pop

        ts = self.daily_past
        self.intermediary_results = {}
        self.intermediary_results['daily_past'] = ts
        self.default_yearly_seasonality = default_yearly_seasonality
        self.intermediary_results_stack = []
        self.model_yearly_seasonality = model_weekly_seasonality
        self.model_weekly_seasonality = model_weekly_seasonality

        self.steps_prediction = pd.DataFrame([
            {
                'step_name': 'add_one',
                'condition': True,
                'output_name_do': 'ts_plusone',
                'output_name_undo': 'ts_plusone_undone',
                'error_do': '',
                'error_undo': '',
                'arguments_do': {},
                'arguments_undo': {},
                'feedback_undo': False,
                'step_description': 'add one to not take the log of zero',
                'step_function_do': self.add_one_do,
                'step_function_undo': self.add_one_undo,
            },
            {
                'step_name': 'log',
                'condition': True,
                'output_name_do': 'ts_log',
                'output_name_undo': 'ts_log_undone',
                'error_do': '',
                'error_undo': '',
                'arguments_do': {},
                'arguments_undo': {},
                'feedback_undo': False,
                'step_description': 'take log to stabilize',
                'step_function_do': self.log_do,
                'step_function_undo': self.log_undo,
            },
            {
                'step_name': 'remove_weekly_seasonality',
                'condition': model_weekly_seasonality,
                'output_name_do': 'ts_no7dseasonality',
                'output_name_undo': 'ts_no7dseasonality_undone',
                'error_do': 'No weekly seasonality, stopping the computation',
                'error_undo': '',
                'arguments_do': {},
                'arguments_undo': {},
                'feedback_undo': False,
                'step_description': 'divide each value by the average value of its weekday, then multiplied by overall average value',
                'step_function_do': self.remove_weekly_seasonality_do,
                'step_function_undo': self.remove_weekly_seasonality_undo,
            },
            {
                'step_name': 'remove_yearly_seasonality',
                'condition': model_yearly_seasonality,
                'output_name_do': 'ts_noYseasonality',
                'output_name_undo': 'ts_noYseasonality_undone',
                'error_do': '',
                'error_undo': '',
                'arguments_do': {'rolavg_duration': rolavg_duration},
                'arguments_undo': {},
                'feedback_undo': False,
                'step_description': 'remove yearly seasonality',
                'step_function_do': self.remove_yearly_seasonality_do,
                'step_function_undo': self.remove_yearly_seasonality_undo,
            },
            {
                'step_name': 'remove_trend',
                'condition': True,
                'output_name_do': 'ts_notrend',
                'output_name_undo': 'ts_notrend_undone',
                'error_do': 'Could not remove the trend from the series, stopping the computation',
                'error_undo': '',
                'arguments_do': {'rolavg_duration': rolavg_duration},
                'arguments_undo': {'rolavg_duration': rolavg_duration},
                'feedback_undo': True,
                'step_description': 'remove trend',
                'step_function_do': self.remove_trend_do,
                'step_function_undo': self.remove_trend_undo,
            },
            {
                'step_name': 'predict_stationary_series_by_week',
                'condition': True,
                'output_name_do': 'ts_pred',
                'output_name_undo': 'ts_pred_undone',
                'error_do': 'error when predicting the stationary series by week',
                'error_undo': '',
                'arguments_do': {},
                'arguments_undo': {},
                'feedback_undo': False,
                'step_description': 'predict stationary series',
                'step_function_do': self.predict_stationary_series_by_week,
                'step_function_undo': lambda x: x,  # do nothing
            },
        ])

        # keep only the steps that we are going to perform
        self.steps_prediction = self.steps_prediction[self.steps_prediction.condition == True]

        # creating stack and queue
        for step_name, row in self.steps_prediction.iterrows():
            do_queue.append(row)
            undo_stack.append(row)

        # executing queue (do) and then stack (undo)
        while do_queue:
            row = do_queue.popleft()
            #       print '--------------' + row.step_name

            # create arguments for the function:
            #      feedback_dict = {}
            #       for n in row.feedback_do:
            #         feedback_dict[n]=self.intermediary_results[n]
            kwargs_dict = row.arguments_do  # dict(row.arguments_do.items() + feedback_dict.items())

            # call function
            ts = row.step_function_do(ts, **kwargs_dict)
            # print row.step_function_do.__name__

            if ts is None:  # function did not return anything, there is an error
                print row.error_do
                return None
            self.intermediary_results[row.output_name_do] = ts
            self.intermediary_results_stack.append(
                ts)  # we will pop each time we do an 'undo' step to get on the intermediary result of the previous 'do' step
            if plot == True: self.plot_ts(ts, title=row.output_name_do)

        self.intermediary_results_stack.pop()  # remove the last intermediary result so that the top of the stack is the result outputted by the last undone step

        while undo_stack:
            row = undo_stack.pop()
            # print row.output_name_undo
            # create arguments for the function
            # if there is a results to be removed, remove it and memorize to pass as parameter if needed
            if self.intermediary_results_stack: result_last_do = self.intermediary_results_stack.pop()
            if row.feedback_undo:
                feedback_dict = {'result_last_do': result_last_do}
            else:
                feedback_dict = {}
            # nargs = len(row.feedback_undo)
            #       for argname, valuename in zip(row.step_function_undo.__code__.co_varnames[2:2+nargs], row.feedback_undo):
            #         feedback_dict[argname]=self.intermediary_results[valuename]
            kwargs_dict = dict(row.arguments_undo.items() + feedback_dict.items())

            # call function
            ts = row.step_function_undo(ts, **kwargs_dict)

            if ts is None:
                print row.error_undo
                return None
            self.intermediary_results[row.output_name_undo] = ts
            if plot == True: self.plot_ts(ts, title=row.output_name_undo)

        return ts

    # def print_steps(self):
    #     for var, var_undone in [('daily_past', self.steps_prediction.output_name_undo.iloc[0])] + zip(
    #             self.steps_prediction.output_name_do.iloc[:-1], self.steps_prediction.output_name_undo.iloc[1:]):
    #         fig = plt.figure(figsize=(10, 5))
    #         ax = fig.add_subplot(111)
    #         ax.set_title(var)
    #
    #         ts_past = self.intermediary_results[var]
    #         ax.plot(ts_past.index, ts_past)
    #
    #         if var_undone in self.intermediary_results.keys():
    #             ts_pred = self.intermediary_results[var_undone]
    #             ax.plot(ts_pred.index, ts_pred)
    #
    #         ax.set_xlim(left=pd.to_datetime('2015-08-01'), right='2018-06-01')
    #
    #         ax.legend()
    #         fig.show()