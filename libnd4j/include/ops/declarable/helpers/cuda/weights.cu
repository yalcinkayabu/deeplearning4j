/*******************************************************************************
 * Copyright (c) 2015-2018 Skymind, Inc.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License, Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0.
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 ******************************************************************************/

//
//  @author sgazeos@gmail.com
//

#include <ops/declarable/helpers/weights.h>

namespace nd4j {
namespace ops {
namespace helpers {



    template <typename T>
    static __device__ void adjustWeightsKernelD(void* inputBuffer,   Nd4jLong* inputShape,
                                               void* weightsBuffer, Nd4jLong* weightsShape,
                                               void* outputBuffer,  Nd4jLong* outputShape,
                                               Nd4jLong inputLength, Nd4jLong weightsLength,
                                               Nd4jLong outputLength, int maxLength) {

        auto tid = threadIdx.x;
        int threadCount = gridDim.x * blockDim.x;
        __shared__ T* outputPart;
        __shared__ Nd4jLong offset;
        //for (int e = 0; e < inputLength; e++) {
        for (Nd4jLong e = tid; e < inputLength; e += blockDim.x) {
            printf("%d %d %d\n", blockIdx.x, blockDim.x, threadIdx.x);

            Nd4jLong xOffset = shape::getIndexOffset(e, inputShape, inputLength);
            int val = *(reinterpret_cast<int*>(inputBuffer) + xOffset);
            if (val < maxLength) {
                Nd4jLong zOffset = shape::getIndexOffset(val, outputShape, outputLength);
                if (weightsBuffer != nullptr) {
                    Nd4jLong yOffset = shape::getIndexOffset(e, weightsShape, weightsLength);
                    //atomicAdd();
                    //reinterpret_cast<T *>(outputBuffer)[0] +=  reinterpret_cast<T *>(weightsBuffer)[yOffset];
                    nd4j::math::atomics::nd4j_atomicAdd(reinterpret_cast<T *>(outputBuffer), reinterpret_cast<T *>(weightsBuffer)[yOffset]); //output->p(val, output->e<T>(val) + 1);
                }
                else {
                    //printf("outputBuffer[0] = %d\n", static_cast<int>(*(reinterpret_cast<T *>(outputBuffer))));
                    nd4j::math::atomics::nd4j_atomicAdd(reinterpret_cast<T *>(outputBuffer), T(1)); //output->p(val, output->e<T>(val) + 1);
                    //            printf("outputBuffer[%ld] = %d\n", zOffset, static_cast<int>(*(reinterpret_cast<T *>(outputBuffer) + zOffset)));
                }
                //printf("xOffset is %ld, zOffset is %ld\n", xOffset, zOffset);
            }
        }
        if (threadIdx.x + offset < outputLength)
            reinterpret_cast<T *>(outputBuffer)[threadIdx.x + offset] = outputPart[threadIdx.x];
    }

        template <typename T>
    static __global__ void adjustWeightsKernel(void* inputBuffer,   Nd4jLong* inputShape,
                                               void* weightsBuffer, Nd4jLong* weightsShape,
                                               void* outputBuffer,  Nd4jLong* outputShape,
                                               int minLength, int maxLength) {

        //auto tid = blockIdx.x * blockDim.x + threadIdx.x; // * blockDim.x; // + threadIdx.x;
        int threadCount = gridDim.x * blockDim.x;
        Nd4jLong inputLength = shape::length(inputShape);
        Nd4jLong weightsLength = 0;
        if (weightsBuffer != nullptr)
            weightsLength = shape::length(weightsShape);

        Nd4jLong outputLength = shape::length(outputShape);
        Nd4jLong borderLen = 1;//outputLength / gridDim.x + outputLength % gridDim.x;

        for (Nd4jLong e = blockIdx.x; e < outputLength; e += threadCount) {
        //if (blockIdx.x < outputLength) {
            //if (e + threadCount < outputLength) {
            Nd4jLong zOffset = shape::getIndexOffset(e, outputShape, outputLength);
            //printf("%d %d %d\n", blockIdx.x, blockDim.x, threadIdx.x);
            Nd4jLong borderLen = 1;
            T* outputBufferZ = reinterpret_cast<T*>(outputBuffer) + zOffset;
            adjustWeightsKernelD<T>(inputBuffer, inputShape, weightsBuffer, weightsShape, (void*)outputBufferZ, outputShape,
                                 inputLength, weightsLength, borderLen, maxLength);

        }
    }

    template <typename T>
    static void adjustWeights_(graph::LaunchContext* context, NDArray* input, NDArray* weights, NDArray* output, int minLength, int maxLength) {
//        for (int e = 0; e < input->lengthOf(); e++) {
//            int val = input->e<int>(e);
//            if (val < maxLength) {
//                if (weights != nullptr)
//                    output->p(val, output->e<T>(val) + weights->e<T>(e));
//                else
//                    output->p(val, output->e<T>(val) + 1);
//            }
//        }
        dim3 launchDims(256, 512, 8192);
        auto stream = context->getCudaStream();
        adjustWeightsKernel<T><<<launchDims.x, launchDims.y, launchDims.z, *stream>>>(input->specialBuffer(),
                input->getSpecialShapeInfo(), weights?weights->specialBuffer():nullptr, weights?weights->getSpecialShapeInfo():nullptr,
                output->specialBuffer(), output->specialShapeInfo(), minLength, maxLength);
    }

    void adjustWeights(graph::LaunchContext* context, NDArray* input, NDArray* weights, NDArray* output, int minLength, int maxLength) {
        BUILD_SINGLE_SELECTOR(output->dataType(), adjustWeights_, (context, input, weights, output, minLength, maxLength), LIBND4J_TYPES);
    }

    BUILD_SINGLE_TEMPLATE(template void adjustWeights_, (graph::LaunchContext* context, NDArray* input, NDArray* weights, NDArray* output, int minLength, int maxLength), LIBND4J_TYPES);
}
}
}