#   Copyright (c) 2019 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from main import test_main

import sys
sys.path.append("..")
from common import paddle_api_benchmark as paddle_api
from common import tensorflow_api_benchmark as tensorflow_api


class BatchNormConfig(object):
    def __init__(self, input_shape):
        self.input_shape = input_shape
        self.data_format = "NHWC"
        self.epsilon = 0.001

    @property
    def num_channels(self):
        if self.data_format == "NHWC":
            return self.input_shape[3]
        else:
            return self.input_shape[1]

    @property
    def axes(self):
        if self.data_format == "NHWC":
            return [0, 1, 2]


config = BatchNormConfig(input_shape=[10, 100, 100, 32])


class PDBatchNorm(paddle_api.PaddleAPIBenchmarkBase):
    def build_program(self, backward=False, dtype=None):
        import paddle.fluid as fluid

        self.name = "batch_norm"
        with fluid.program_guard(self.main_program, self.startup_program):
            input = fluid.data(
                name='input',
                shape=config.input_shape,
                dtype='float32',
                lod_level=0)
            scale = fluid.layers.create_parameter(
                name='scale', shape=[config.num_channels], dtype="float32")
            bias = fluid.layers.create_parameter(
                name='bias', shape=[config.num_channels], dtype="float32")
            input.stop_gradient = False
            result = fluid.layers.batch_norm(
                input=input,
                act=None,
                is_test=False,
                momentum=0.9,
                epsilon=config.epsilon,
                param_attr="scale",
                bias_attr="bias",
                data_layout=config.data_format)

            self.feed_vars = [input, scale, bias]
            self.fetch_vars = [result]
            if backward:
                self.append_gradients(result, [input, scale, bias])


class TFBatchNorm(tensorflow_api.TensorflowAPIBenchmarkBase):
    def build_graph(self, backward=False, dtype=None):
        import tensorflow as tf

        self.name = "batch_norm"
        self.allow_growth = True

        input = tf.placeholder(
            name='input', shape=config.input_shape, dtype=tf.float32)
        scale = tf.placeholder(
            name='scale', shape=[config.num_channels], dtype=tf.float32)
        bias = tf.placeholder(
            name='bias', shape=[config.num_channels], dtype=tf.float32)
        mean, var = tf.nn.moments(
            x=input, axes=config.axes, shift=None, keepdims=False)
        result = tf.nn.batch_normalization(
            x=input,
            mean=mean,
            variance=var,
            offset=bias,
            scale=scale,
            variance_epsilon=config.epsilon)

        self.feed_list = [input, scale, bias]
        self.fetch_list = [result]
        if backward:
            self.append_gradients(result, [input, scale, bias])


if __name__ == '__main__':
    test_main(PDBatchNorm(), TFBatchNorm(), feed_spec=None)
