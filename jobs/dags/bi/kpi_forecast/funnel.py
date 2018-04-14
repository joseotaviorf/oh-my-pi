import pandas as pd
import matplotlib as plt
import numpy as np

class Funnel:
    """
    The funnel class takes as definition the steps of the funnel and a number of parameters that will help it
    define its properties (the distributions)
    """

    def __init__(self,
                 steps,  # deduplication_col	order	predict_with	step	q_threshold
                 train_df,  # we do not to give any info about the future away. contains lines at most n_training_days old, up to today
                 begin_pred,
                 end_pred,
                 range_recent_day,
                 range_pred_day,
                 default_distribs=None,
                 min_samples=1000,
                 max_samples=4000
                 ):
        # store parameters
        self.steps = steps
        self.train_df = train_df
        self.begin_pred = begin_pred
        self.end_pred = end_pred
        self.range_recent_day = range_recent_day
        self.range_pred_day = range_pred_day
        self.default_distribs = default_distribs
        self.min_samples = min_samples
        self.max_samples = max_samples

        # setup
        self.__find_step_thresholds()
        # self.display_step_thresholds()
        self.__compute_distribs()

    def __find_step_thresholds(self):
        """
        adds a column q_threshold to the steps dataframe.

        it takes less than or equal to q_threshold days to get from predict_with to step.

        purpose : *to determine the distribution (with training_data)*, we will ignore all events that have happened
        less than q_threshold days ago.

        eg if q_threshold=4 days, we will ignore events from d-1, d-2,d-3 and d-4
        (if an event happened on d-4, the 95th pc will happen on d-0, which is a day we are trying to predict)
        """

        # we want to determine the time-to-next-step
        # based on processes that have started between 14 days ago and two months before that.
        analysis_df = self.train_df[
            (self.train_df[self.steps.index[0]] < (self.begin_pred - pd.to_timedelta(14, unit='days'))) & #needed ?
            (self.train_df[self.steps.index[0]] >= (self.begin_pred - pd.to_timedelta(14 + 60, unit='days')))].copy()

        self.steps['q_threshold'] = np.nan
        self.process_duration = pd.DataFrame()  # DF with one column per step and as many lines as analysis_df, where we store the duration of each process. stored in a dataframe just so we can display the histogram later

        for step, row_step in self.steps.iterrows():  # predicted step
            deduplication_col_step = row_step.deduplication_col
            predictor_step = row_step.predict_with

            if predictor_step is not None:
                row_predictor_step = self.steps.loc[predictor_step]
                # store duration information for later display
                self.process_duration[step] = analysis_df[step].dt.date - analysis_df[predictor_step].dt.date

                # we deduplicate analysis df for deduplication_col_step since we do not want to double count them
                t = analysis_df[
                    analysis_df[predictor_step].notnull() &
                    analysis_df[step].notnull() &
                    (~analysis_df.duplicated(subset=[deduplication_col_step]))
                ] #we need step and predictor step to be not null to be able to define a duration
                if t.shape[0]>0:
                    step_duration_deduplicated = t[step].dt.date - t[predictor_step].dt.date
                    step_duration_deduplicated = step_duration_deduplicated[step_duration_deduplicated.notnull()]
                    self.steps.loc[step, 'q_threshold'] = pd.to_timedelta(step_duration_deduplicated.quantile(q=.95).days, unit='days')
                else:
                    print 'no durations for step ' + step
                    self.steps.loc[step, 'q_threshold'] = np.nan


    def display_step_thresholds(self):
        """display the histogram of the time between a step and its predictor"""
        fig = plt.figure(figsize=(10, 5))
        ax = fig.add_subplot(111)
        ax.set_title('histogram of time between steps, with 95percentile mark')

        for step in self.process_duration.columns:
            predictor_step = self.steps.loc[step].predict_with
            nonnull_process_duration = self.process_duration.loc[self.process_duration[step].notnull(), step]
            a = ax.hist(nonnull_process_duration[(nonnull_process_duration.dt.days < 30) &
                                                 (nonnull_process_duration.dt.days > -10)].dt.days,
                        label=predictor_step + ' to ' + step, normed=True,
                        bins=20,
                        alpha=0.5)
            ax.axvline(self.steps.loc[step, 'q_threshold'].days, ls='--', alpha=0.4, color=a[-1][0].get_facecolor())

        ax.legend()
        fig.show()

    def __compute_distribs(self):
        """computes conversion distribution between step and step +1"""

        self.distribs = pd.DataFrame()

        # we want to compute, for each weekday, step and predictor_step, how many days there are between a predictor step an the step

        for step, row_step in self.steps.iterrows():  # predicted step
            deduplication_col_step = row_step.deduplication_col
            predictor_step = row_step.predict_with
            q_threshold = row_step.q_threshold  # need to wait <=q_t days between predictor and predicted in 95% of cases

            if predictor_step is not None:
                row_predictor_step = self.steps.loc[predictor_step]
                deduplication_col_predictor_step = row_predictor_step.deduplication_col

                for weekday in range(0, 7):
                    # take the train df, select the lines where the predictor step happened,
                    # and it happened on that day of the week
                    # and it happened more than q_t days ago
                    t = self.train_df[self.train_df[predictor_step].notnull() &
                                      (self.train_df[predictor_step].dt.weekday == weekday) &
                                      (self.train_df[predictor_step] < self.begin_pred - q_threshold)].copy()
                    # find the date for which we have a significant number of steps that have happened
                    n_events = t.groupby(t[step].dt.date).size()  # we count the number of steps that happen per day
                    n_events = n_events.sort_index(ascending=False).cumsum()  # we order them by decreasing dates
                    threshold_date = n_events[
                        n_events > self.max_samples].index.max()  # we select the last date for which the cumsum of what follows is larger tahn a threshold
                    if pd.notnull(threshold_date):  # there is a date after which enough events happen
                        t = t[t[predictor_step] >= threshold_date]

                    # how many distinct instances of the the step are there for this particular weekday?
                    unique_predictor_id = t[deduplication_col_predictor_step].nunique()

                    # keep only the lines of t that have a predicted step
                    u = t[t[step].notnull()].copy()
                    # deduplicate the column of the predicted step. we assume the lines we delete all have the same first step as their duplicate next_step
                    u = u[(~u.duplicated(subset=[deduplication_col_step]))]  # | (t[deduplication_col_next_step]==-1)
                    # take the difference of the step date and the predictor step date
                    u[predictor_step + '_to_' + step] = u[step].dt.date - u[
                        predictor_step].dt.date  # we want the difference in days, not hours
                    # store the distribution of delays
                    n_samples = u.shape[0]
                    distrib = u[predictor_step + '_to_' + step].value_counts() / unique_predictor_id
                    self.distribs = self.distribs.append({'predictor_step': predictor_step,
                                                          'weekday': weekday,
                                                          'step': step,
                                                          'distrib': distrib,
                                                          'conversion_rate': distrib.sum(),
                                                          'samples': n_samples,
                                                          # number of steps on which the distrib is based
                                                          'unique_predictor_id': unique_predictor_id,
                                                          'threshold_date': threshold_date,
                                                          },
                                                         ignore_index=True)
        self.distribs = self.distribs.set_index(['predictor_step', 'weekday', 'step'])

    def get_prior_knowledge_distrib(self, distrib, min_days_to_next_event=None):
        """function to compute the distributions with knowledge of number of idle days.
        transform distribution with prior knowledge
        in case the event happened in the recent_df,
        we know the next step didn't happen yet (not on begin_pred or before)"""

        pc_null = 1 - distrib.sum()
        prior_knowledge_distrib = distrib.loc[distrib.index >= pd.to_timedelta(min_days_to_next_event, unit='days')]
        prior_knowledge_distrib = prior_knowledge_distrib / (prior_knowledge_distrib.sum() + pc_null)
        return prior_knowledge_distrib

    def __compute_predictors(self):
        """
        create a dataframe with a column for each step that we need to predict
        the predictor df contains, for each step to be predicted,
        the number of lines in the predictor step when we ignore steps between the
        predictor step and the step to be predicted
        """

        self.predictor_df = pd.DataFrame()  # index=range_recent_day.tolist()+range_pred_day.tolist())

        for step, row_step in self.steps.iterrows():  # predicted step
            # deduplication_col_step = row_step.deduplication_col
            predictor_step = row_step.predict_with
            step_order = row_step.order

            if predictor_step is not None:  # we need to predict this step
                row_predictor_step = self.steps.loc[predictor_step]
                # deduplication_col_predictor_step = row_predictor_step.deduplication_col

                # find the lines in recent_df that have performed predictor_step but not step,
                # !! at the time of begin_pred !!
                # and count them by predictor_step_date
                sel = self.recent_df[self.recent_df[predictor_step].notnull() &  # have perfomed predictor step
                                     (self.recent_df[predictor_step] < self.begin_pred) &  # have performed it before at the time of the prediction
                                     (self.recent_df['last_step_order'] < step_order)]  # have not preformed the step to be predicted or any step further

                col = sel.groupby(pd.to_datetime(self.recent_df[predictor_step].dt.date)).size()
                col = col.rename(step)
                col.index = col.index.rename('prediction_date')

                df_col = pd.DataFrame(col)

                # if a region has no predictors regardless of the step (nothing happened recently
                # that can lead to another event), this region will not appear in the dataframe of predictors
                self.predictor_df = pd.concat([self.predictor_df, df_col],
                                              axis=1)  # we are adding columns corresponding to the different steps

        self.predictor_df = self.predictor_df.fillna(0.0)

    def __add_last_step_date_and_name(self):
        self.recent_df['last_step_name'] = np.nan  # name of step
        self.recent_df['last_step_date'] = np.nan  # date of step
        self.recent_df['last_step_weekday'] = np.nan  # weekday (0..6)
        self.recent_df['last_step_order'] = np.nan  # 1...n

        # The last step performed -- before the date begin pred !! --

        for step in self.steps.index[
                    ::-1]:  # go in reverse order. where there is no last step yet and step is not null, last_step = step

            # if there is no last step and step is not null and step>begin_pred => the date of the last step is the date of the step
            self.recent_df.loc[self.recent_df['last_step_name'].isnull() &
                               (self.recent_df[step] < self.begin_pred), 'last_step_date'] = self.recent_df.loc[
                self.recent_df['last_step_name'].isnull() & (self.recent_df[
                                                                 step] < self.begin_pred), step].dt.date  # date of the step for the lines for which it is the last step
            # the order is the order of the last step
            self.recent_df.loc[self.recent_df['last_step_name'].isnull() &
                               (self.recent_df[step] < self.begin_pred), 'last_step_order'] = self.steps.loc[step].order
            # and the last step is the step
            self.recent_df.loc[self.recent_df['last_step_name'].isnull() &
                               (self.recent_df[step] < self.begin_pred), 'last_step_name'] = step

        # finally, the weekday of the last step date
        self.recent_df.loc[self.recent_df.last_step_date.notnull(), 'last_step_weekday'] = self.recent_df[
            'last_step_date'].apply(lambda x: pd.Timestamp(x).weekday())
        self.recent_df.loc[:, 'last_step_date'] = pd.to_datetime(self.recent_df.last_step_date)

        # we want to keep one line per 'flow',
        # in other words one line per sk_booking (self.steps['deduplication_col'][0]),
        # the one with the furthest progress (or the latest date in case of equality)
        self.recent_df = self.recent_df.sort_values(
            [self.steps['deduplication_col'][0], 'last_step_order', 'last_step_date'], ascending=False).groupby(
            self.steps['deduplication_col'][0]).agg('first').reset_index()

    def predict(self, recent_df, ts_pred):
        """
        makes a prediction based on :
        recent_df, turned into predictor_df : how many initiated processes we should consider when applying the conversion distribution
        ts_pred : the predicted bookings over range_pred_day, for regions where a prediction was possible

        for every step in the funnel after the first one,
        for every date in range_pred_date

        IF:
        a prediction was able to be made for the region AND (condition outside this function)
        a predictor was able to be made for the region
        """

        # update the state of the Funnel
        self.ts_pred = ts_pred
        self.recent_df = recent_df

        # transform the data
        self.__add_last_step_date_and_name()  # transforms recent_df
        self.__compute_predictors()  # computes self.predictor_df

        # we don't include the first step of hte process because it is being predicted,
        # and we will concatenate it with the rest
        kpi_pred = pd.DataFrame(index=self.range_recent_day.tolist() + self.range_pred_day.tolist(),
                                columns=self.steps.index[1:].tolist())
        kpi_pred = pd.concat([kpi_pred, self.ts_pred], axis=1)  # include the first step that is already predicted
        kpi_pred = kpi_pred[self.steps.index.tolist()]  # reorder the steps (first one first)
        kpi_pred = kpi_pred.fillna(0.0)

        ##for every step in the funnel, apply the distribution to the relevant column in kpi_pred to predict it
        for step, row_step in self.steps.iterrows():  # predicted step
            predictor_step = row_step.predict_with
            if predictor_step is not None:  # has to be predicted
                # create a temporary series that will host the number of applications per day
                final_predictor = pd.concat([kpi_pred.loc[:, predictor_step],
                                             self.predictor_df.loc[:, step]], axis=1).sum(
                    axis=1)  # .reset_index(level=0,drop=True)

                for predictor_step_date in final_predictor[
                            final_predictor > 0].index:  # the dates for which the predictor of step is positive
                    weekday = predictor_step_date.weekday()
                    # we know that the applications made at this date stayed idle at least until
                    # the morning of begin_pred. no event can be predicted backwards before begin_pred
                    min_days_to_next_event = (self.begin_pred - predictor_step_date) / pd.to_timedelta(1,unit='days')
                    distrib = self.distribs.loc[(predictor_step, float(weekday), step), 'distrib']
                    samples = self.distribs.loc[(predictor_step, float(weekday), step), 'samples']
                    if samples < self.min_samples and self.default_distribs is not None:
                        'too few samples, using default distrib for step ' + step + ' on day ' + str(weekday)
                        distrib = self.default_distribs.loc[(predictor_step, float(weekday), step), 'distrib']
                    distrib = self.get_prior_knowledge_distrib(distrib, min_days_to_next_event)
                    for delay, conv in distrib.iteritems():
                        if predictor_step_date + delay in kpi_pred.index:
                            kpi_pred.loc[predictor_step_date + delay, step] = kpi_pred.loc[
                                                                                  predictor_step_date + delay, step] + \
                                                                              final_predictor[
                                                                                  predictor_step_date] * conv

        kpi_pred = kpi_pred.loc[self.range_pred_day.tolist(), :]
        kpi_pred.index.set_names(['date'], inplace=True)

        return kpi_pred