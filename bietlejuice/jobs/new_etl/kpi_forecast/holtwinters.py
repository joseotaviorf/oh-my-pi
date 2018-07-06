from __future__ import division

from math import sqrt
from sys import exit

from numpy import array
from scipy.optimize import minimize


def RMSE(params, *args):
    '''we compute the distance between true and predicted, when we predict deltat periods into the future'''
    Y = args[0]
    type = args[1]
    rmse = 0
    deltat = args[3]
    if type == 'linear':
        # if initial values are defined, use them
        [a0, b0, y0] = args[2]
        a = [a0]
        b = [b0]
        y = [y0]
        if a0 is None:
            a = [Y[0] * 1.41]
        if b0 is None:
            b = [(Y[min(10, len(Y) - 1)] - Y[0]) / 10]
        if y0 is None:
            y = [Y[0] * 1.19]

        for d in range(1, deltat):
            y.append(y[0])

        alpha, beta = params

        for i in range(len(Y)):
            a.append(alpha * Y[i] + (1 - alpha) * (a[i] + b[i]))
            b.append(beta * (a[i + 1] - a[i]) + (1 - beta) * b[i])
            y.append(a[i + 1] + deltat * b[i + 1])

    else:

        alpha, beta, gamma = params
        m = args[2]
        a = [sum(Y[0:m]) / float(m)]
        b = [(sum(Y[m:2 * m]) - sum(Y[0:m])) / m ** 2]

        if type == 'additive':

            s = [Y[i] - a[0] for i in range(m)]
            y = [a[0] + b[0] + s[0]]

            for i in range(len(Y)):
                a.append(alpha * (Y[i] - s[i]) + (1 - alpha) * (a[i] + b[i]))
                b.append(beta * (a[i + 1] - a[i]) + (1 - beta) * b[i])
                s.append(gamma * (Y[i] - a[i] - b[i]) + (1 - gamma) * s[i])
                y.append(a[i + 1] + b[i + 1] + s[i + 1])

        elif type == 'multiplicative':

            s = [Y[i] / a[0] for i in range(m)]
            y = [(a[0] + b[0]) * s[0]]

            for i in range(len(Y)):
                a.append(alpha * (Y[i] / s[i]) + (1 - alpha) * (a[i] + b[i]))
                b.append(beta * (a[i + 1] - a[i]) + (1 - beta) * b[i])
                s.append(gamma * (Y[i] / (a[i] + b[i])) + (1 - gamma) * s[i])
                y.append((a[i + 1] + b[i + 1]) * s[i + 1])

        else:

            exit('Type must be either linear, additive or multiplicative')
    # distance between true value and value predicted based on info available at t-deltat
    # we want to compare Y[2] with y[2], which was filled knowing Y[2-deltat]
    rmse = sqrt(sum([(o - p) ** 2 for o, p in zip(Y[deltat:], y[deltat:-1])]) / len(Y[1:]))

    return rmse


def linear(x, fc, alpha=None, beta=None, a0=None, b0=None, y0=None, deltat=6):
    Y = x[:]
    # optimize greeks if alpha or beta are None
    if (alpha is None) or (beta is None):
        initial_values = array([0.4, 0.3])
        boundaries = [(0, 1), (0, 1)]
        type = 'linear'

        result = minimize(RMSE, x0=initial_values, args=(Y, type, [a0, b0, y0], deltat), method='L-BFGS-B',
                          bounds=boundaries)
        alpha, beta = result.x

    # initial values
    a = [a0]
    b = [b0]
    y = [y0]
    if a0 is None:
        a = [Y[0]]
    if b0 is None:
        b = [(Y[min(10, len(Y) - 1)] - Y[0]) / 10]  # [(Y[-1] - Y[1])/len(Y)] # b = [Y[1] - Y[0]]
    if y0 is None:
        y = [Y[0]]  # [a[0] + b[0]] #what we think is going to happen in 1
    rmse = 0

    # run
    for i in range(len(Y) + fc):
        if i == len(Y):
            Y.append(a[-1] + b[-1])  # i = 25. in the previous iteration (i=24) we have filled a[25], b[25], y[25]
        a.append(alpha * Y[i] + (1 - alpha) * (a[i] + b[i]))
        b.append(beta * (a[i + 1] - a[i]) + (1 - beta) * b[i])
        y.append(a[i + 1] + b[i + 1])

    rmse = sqrt(sum([(m - n) ** 2 for m, n in zip(Y[1:-fc], y[1:-fc - 1])]) / len(Y[1:-fc]))

    return Y[-fc:], alpha, beta, rmse, [a, b, y], result.success
