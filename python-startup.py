import sys
import math
import re


from matplotlib import pyplot as plt
import numpy as np

from IPython.display import display as d

from calc import show_result as p

def ts():
    from tensorflow import keras
    from keras.datasets import mnist
    from keras.utils import np_utils, to_categorical
    from keras import models
    from keras import layers
