""" 
This script applies a pretrained model file to a large image volume saved in hdf5 or n5 format.
"""
import argparse
import sys
import random
import numpy as np
import os
import sys
import time
import tensorflow as tf
from tensorflow.keras.models import load_model
from tqdm import tqdm

import tools.tilingStrategy as tilingStrategy
import unet.model as model
import tools.postProcessing as postProcessing
import tools.preProcessing as preProcessing

from n5_utils import read_n5_block, write_n5_block

model_input_shape = (220, 220, 220)
model_output_shape = (132, 132, 132)
batch_size = 1  # Tune batch size to speed up computation.

# Specify wheter to run the postprocessing function on the segmentation ouput
postprocessing = True


def _gpu_fix():
    # Fix for tensorflow-gpu issues
    gpus = tf.config.experimental.list_physical_devices('GPU')
    if gpus:
        # Currently, memory growth needs to be the same across GPUs
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)

        logical_gpus = tf.config.experimental.list_logical_devices('GPU')
        print('Physical GPUs:', len(gpus), 'Logical GPUs:', len(logical_gpus))


def main():
    parser = argparse.ArgumentParser(description='Neuron segmentation')

    parser.add_argument('-i', '--input',
                        dest='input_path', type=str, required=True,
                        help='Path to the input n5')

    parser.add_argument('-id', '--input_data_set',
                        dest='input_data_set', type=str, default="/s0",
                        help='Path to input data set (default "/s0")')

    parser.add_argument('-od', '--output_data_set',
                        dest='output_data_set', type=str, default="/s0",
                        help='Path to output data set (default "/s0")')

    parser.add_argument('-m', '--model_path',
                        dest='model_path', type=str, required=True,
                        help='Path to the model')

    parser.add_argument('-s', '--scaling',
                        dest='scaling', type=float,
                        help='Tiles scaling factor')

    parser.add_argument('-o', '--output',
                        dest='output_path', type=str, required=True,
                        help='Path to the (already existing) output n5')

    parser.add_argument('--start',
                        dest='start_coord', type=str, required=True,
                        metavar='x1,y1,z1',
                        help='Starting coordinate (x,y,z) of block to process')

    parser.add_argument('--end',
                        dest='end_coord', type=str, required=True,
                        metavar='x2,y2,z2',
                        help='Ending coordinate (x,y,z) of block to process')

    parser.add_argument('--whole_vol_shape',
                        dest='whole_vol_shape', type=str, required=True,
                        metavar='dx,dy,dz',
                        help='Whole volume shape')

    parser.add_argument('--set_gpu_mem_growth', dest='set_gpu_mem_growth',
                        action='store_true', default=False,
                        help='If true keep the tiffs generated by the watershed')

    parser.add_argument('--with_post_processing', dest='with_post_processing',
                        action='store_true', default=False,
                        help='If true run the watershed segmentation')

    parser.add_argument('-ht', '--high_threshold', dest='high_threshold',
                        type=float, default=0.98,
                        help='High confidence threshold for region closing')

    parser.add_argument('-lt', '--low_threshold', dest='low_threshold',
                        type=float, default=0.2,
                        help='Low confidence threshold for region closing')

    parser.add_argument('--small_region_probability_threshold',
                        dest='small_region_probability_threshold',
                        type=float, default=0.2,
                        help='Probability threshold for small region removal')

    parser.add_argument('--small_region_size_threshold',
                        dest='small_region_size_threshold',
                        type=int, default=2000,
                        help='Size threshold for small region removal')

    args = parser.parse_args()

    if args.set_gpu_mem_growth:
        _gpu_fix()

    start = tuple([int(d) for d in args.start_coord.split(',')])
    end = tuple([int(d) for d in args.end_coord.split(',')])

    # Parse the tiling subvolume from slice to aabb notation
    subvolume = np.array(start + end)
    subvolume_shape = tuple([end[i] - start[i] for i in range(len(end))])

    # Create a tiling of the subvolume using absolute coordinates
    print('targeted subvolume for segmentation:', subvolume)
    whole_vol_shape = tuple([int(d) for d in args.whole_vol_shape.split(',')])
    print('global image shape:', str(whole_vol_shape))
    tiling = tilingStrategy.UnetTiling3D(whole_vol_shape,
                                         subvolume,
                                         model_output_shape,
                                         model_input_shape)

     # actual U-Net volume as x0,y0,z0,x1,y1,z1
    input_volume_aabb = np.array(tiling.getInputVolume())
    unet_start = [ np.max([0, d]) for d in input_volume_aabb[:3] ]
    unet_end = [ np.min([whole_vol_shape[i], input_volume_aabb[i+3]]) 
                    for i in range(3) ] # max extent is whole volume shape

    # Read part of the n5 based upon location
    unet_volume = np.array(unet_start + unet_end)

    print('Read U-Net volume', unet_start, unet_end, unet_volume)
    img = read_n5_block(args.input_path, args.input_data_set, unet_start, unet_end)

    # Calculate scaling factor from image data if no predefined value was given
    if args.scaling is None:
        scalingFactor = preProcessing.calculateScalingFactor(img)
    else:
        scalingFactor = args.scaling

    # Apply preprocessing globaly !
    img = preProcessing.scaleImage(img, scalingFactor)

    # %% Load Model File
    # Restore the trained model. Specify where keras can
    # find custom objects that were used to build the unet
    unet = load_model(args.model_path, compile=False,
                      custom_objects={
                          'InputBlock': model.InputBlock,
                          'DownsampleBlock': model.DownsampleBlock,
                          'BottleneckBlock': model.BottleneckBlock,
                          'UpsampleBlock': model.UpsampleBlock,
                          'OutputBlock': model.OutputBlock
                      })

    print('The unet works with\ninput shape {}\noutput shape {}'.format(
        unet.input.shape, unet.output.shape))

    # Create an absolute Canvas from the input region
    # (this is the targeted output expanded by
    # adjacent areas that are relevant for segmentation)
    print('Create tiled input:',whole_vol_shape, unet_volume, img.shape)
    input_canvas = tilingStrategy.AbsoluteCanvas(whole_vol_shape,
                                                 canvas_area=unet_volume,
                                                 image=img)
    # Create an empty absolute canvas for
    # the targeted output region of the mask
    print('Create tiled output:',whole_vol_shape, subvolume, subvolume_shape)
    output_image = np.zeros(shape=subvolume_shape)
    output_canvas = tilingStrategy.AbsoluteCanvas(whole_vol_shape,
                                                  canvas_area=subvolume,
                                                  image=output_image)
    # Create the unet tiler instance
    tiler = tilingStrategy.UnetTiler3D(tiling, input_canvas, output_canvas)

    # Perform segmentation

    def preprocess_dataset(x):
        # The unet expects the input data to have an additional channel axis.
        x = tf.expand_dims(x, axis=-1)
        return x

    predictionset_raw = tf.data.Dataset.from_generator(tiler.getGeneratorFactory(),
                                                       output_types=(
                                                           tf.float32),
                                                       output_shapes=(tf.TensorShape(model_input_shape)))

    predictionset = predictionset_raw.map(
        preprocess_dataset).batch(batch_size).prefetch(2)

    # Counter variable over all tiles
    tile = 0
    progress_bar = tqdm(desc='Tiles processed', total=len(tiler))

    # create an iterator on the tf dataset
    dataset_iterator = iter(predictionset)

    while tile < len(tiler):
        inp = next(dataset_iterator)
        batch = unet.predict(inp)  # predict one batch

        # use softmax on channels and retain object cannel
        batch = tf.nn.softmax(batch, axis=-1)[..., 1]

        # Write each tile in the batch to it's correct location in the output
        for i in range(batch.shape[0]):
            tiler.writeSlice(tile, batch[i, ...])
            tile += 1

        progress_bar.update(batch.shape[0])

    # Apply post Processing globaly
    if(args.with_post_processing):
        postProcessing.clean_floodFill(tiler.mask.image,
            high_confidence_threshold=args.high_threshold,
            low_confidence_threshold=args.low_threshold)
        postProcessing.removeSmallObjects(tiler.mask.image,
            probabilityThreshold=args.small_region_probability_threshold,
            size_threshold=args.small_region_size_threshold)

    # Write to the same block in the output n5
    print('Write segmented volume', start, end, tiler.mask.image.shape)
    write_n5_block(args.output_path, args.output_data_set,
                   start, end, tiler.mask.image)


if __name__ == "__main__":
    main()
