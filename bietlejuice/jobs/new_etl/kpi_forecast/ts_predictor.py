import numpy as np
import pandas as pd
from bietlejuice.jobs.new_etl.kpi_forecast.holtwinters import linear
from qa_python_utils.default_logger import _logger


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
        self.end_ts = self.begin_pred - pd.to_timedelta(1, unit='days')
        self.daily_past = pd.concat(
            [pd.DataFrame(index=pd.date_range(self.begin_ts, self.end_ts, freq='D', closed=None)),
             self.daily_past],
            axis=1).fillna(0.0).iloc[:, 0]

        # cut the end of the series : make sure to cut the series before begin_pred
        # cut the beginning of the series :
        # find the last date at which the bookings were null for one week.
        # the end of that week is the beginning of the period we consider to make predictions
        # if this date does not exit, we do not need to cut the series
        rolling_daily = self.daily_past.rolling(7).sum()
        begin_ts_candidate = pd.to_datetime(rolling_daily[rolling_daily == 0].index.max())
        if pd.notnull(begin_ts_candidate):
            self.begin_ts = begin_ts_candidate
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

    def remove_weekly_seasonality_do(self, ts):
        # find the weekly seasonality: dailylog/dailylog7drollingavg, groupby weekday/sum
        # for each day the average of the last 7 days, not including this day
        rolavg7_ts = self.rolling_mean_until_yesterday(ts, days=7)
        ratio7_ts = ts / rolavg7_ts  # should be close to 1 on average

        # todo : remove specific step:
        ratio7_ts_2y_positive = ratio7_ts.loc[
            (ratio7_ts.index >= pd.Timestamp('1/1/2016')) & (ratio7_ts.index < self.begin_pred) &
            (ratio7_ts > 0).values]

        self.weekly_seasonality = ratio7_ts_2y_positive.groupby(
            ratio7_ts_2y_positive.index.to_series().dt.weekday).mean()  # should be close to 1 on average

        # the sum of a normal week should be 7, not 7.02
        self.weekly_seasonality = self.weekly_seasonality / self.weekly_seasonality.sum() * 7
        if self.weekly_seasonality[self.weekly_seasonality.notnull()].shape[0] < 7:
            _logger.info('Not enough data to compute weekly seasonality')
            return None

        # correct all the days by their weekly seasonality. if 80% of normal,
        # divide by 0.8 (hypothesis weekly and yearly seasonality are independent)
        seasonality_factor_week = self.weekly_seasonality.loc[ts.index.to_series().dt.weekday]  # new
        seasonality_factor_week.index = ts.index
        ts_no7dseasonality = ts.divide(seasonality_factor_week)
        return ts_no7dseasonality

    def remove_weekly_seasonality_undo(self, ts):  # the series we want to add the seasonality to
        seasonality_factor_week_pred = self.weekly_seasonality[self.range_pred_day.to_series().dt.weekday]
        seasonality_factor_week_pred.index = self.range_pred_day
        ts_withweeklyseasonality = seasonality_factor_week_pred * ts
        return ts_withweeklyseasonality

    def optimized_horizons_pred(self, ts):
        """
        predicts, for every horizon, what is the most likely value.

        """
        pred_list = []
        tsw = ts.resample('W-MON', closed='left', label='left').sum().tail(104)
        for dt in range(len(self.range_pred_week)):
            pred, alpha, beta, rmse, [a, b, y], success = linear(tsw.tolist(), len(self.range_pred_week), deltat=dt)
            if alpha == 0 or (not success):
                pred, alpha, beta, rmse, [a, b, y], success = linear(tsw.tolist(), len(self.range_pred_week), a0=0, b0=0, y0=0, deltat=dt)
                if alpha == 0 or (not success):
                    _logger.info('second optimization failed')
                    pred_list.append(None)
                else:
                    pred_list.append(pred[dt])
            else:
                pred_list.append(pred[dt])
        ts_pred_weekly = pd.Series(data=pred_list, index=self.range_pred_week, name=self.daily_past.name).ffill()
        ts_pred = ts_pred_weekly.resample('D').ffill()[self.range_pred_day].ffill() / 7

        return ts_pred

    def predict(self):
        """
        returns the prediction over range_pred_day
        """
        pred_ts = None
        ts = self.daily_past
        # self.default_yearly_seasonality = default_yearly_seasonality

        ts_p1 = ts + 1
        ts_p1_log = np.log(ts_p1)
        ts_p1_log_nws = self.remove_weekly_seasonality_do(ts_p1_log)
        if ts_p1_log_nws is not None:
            ts_p1_nws = np.exp(ts_p1_log_nws)
            ts_nws = ts_p1_nws - 1
            ts_nws.loc[ts_nws < 0] = 0

            # get values here to test
            pred_ts_nws = self.optimized_horizons_pred(ts_nws)

            pred_ts_p1_nws = pred_ts_nws + 1
            pred_ts_p1_log_nws = np.log(pred_ts_p1_nws)
            pred_ts_p1_log = self.remove_weekly_seasonality_undo(pred_ts_p1_log_nws)
            pred_ts_p1 = np.exp(pred_ts_p1_log)
            pred_ts = pred_ts_p1 - 1
            pred_ts.loc[pred_ts < 0] = 0

        return pred_ts
