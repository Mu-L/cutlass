/***************************************************************************************************
 * Copyright (c) 2023 - 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 **************************************************************************************************/
/*! \file
    \brief Tests for device-wide CONV interface
*/

#include "cutlass_unit_test.h"

#include "cutlass/cutlass.h"
#include "cute/tensor.hpp"
#include "cute/atom/mma_atom.hpp"

#include "cutlass/numeric_types.h"

#include "cutlass/conv/device/conv_universal_adapter.hpp"
#include "cutlass/conv/kernel/conv_universal.hpp"
#include "cutlass/conv/collective/collective_builder.hpp"
#include "cutlass/epilogue/collective/collective_builder.hpp"

#include "../testbed_conv.hpp"
using namespace cute;

#if (defined(CUTLASS_ARCH_MMA_SM100_SUPPORTED) && !defined(CUTLASS_SM100_FAMILY_ARCHS_ENABLED))

// alpha != 1 && beta != 0
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0, 1.0));
}

// alpha != 1 && beta != 0 && bias
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBias<
      ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0, 1.0));
}

// alpha != 1 && beta != 0 && bias && relu
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_relu) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::ReLu, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0, 1.0));
}

// per-channel alpha/beta scaling && bias && relu
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_scaled_bias_relu) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::PerColLinCombPerColBiasEltAct<
      cutlass::epilogue::thread::ReLu, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>());
}

TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_scaled_bias_relu_residual) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementSrc     = int8_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::PerColResAddPerColBiasEltAct<
      cutlass::epilogue::thread::ReLu, ElementOut, ElementCompute, ElementBias, ElementSrc>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      ElementSrc, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<ElementSrc>::value,
      ElementOut, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<ElementOut>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>());
}

// alpha != 1 && beta != 0 && bias && gelu
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_gelu) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::GELU_taylor, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0f, 1.0f, 0.005f));
}

// alpha != 1 && beta != 0 && bias && gelu_erf
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_gelu_erf) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::GELU, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0f, 1.0f, 0.005f));
}

// alpha != 1 && beta != 0 && bias && swish
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_swish) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::SiLu, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0f, 1.0f, 0.005f));
}

// alpha != 1 && beta != 0 && bias && leakyrelu
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_leakyrelu) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::LeakyReLU, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0f, 1.0f, 0.005f));
}


// alpha != 1 && beta != 0 && bias && hardswish
TEST(SM100_device_conv3d_fprop_implicitgemm_s8ndhwc_s8ndhwc_s32ndhwc_tensor_op_s32, 64x64x64_1x1x1_alpha_beta_bias_hardswish) {
  using ElementAct     = int8_t;
  using ElementFlt     = int8_t;
  using ElementOut     = int32_t;
  using ElementAcc     = int32_t;
  using ElementCompute = float;
  using ElementBias = float;
  using MmaTileShape = Shape<_64, _64, Shape<_64>>;
  using ClusterShape = Shape<_1,_1,_1>;

  using FusionOperation = cutlass::epilogue::fusion::LinCombPerColBiasEltAct<
      cutlass::epilogue::thread::ScaledHardSwish, ElementOut, ElementCompute, ElementBias>;
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      MmaTileShape, ClusterShape,
      cutlass::epilogue::collective::EpilogueTileAuto,
      ElementAcc, ElementCompute,
      int8_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int8_t>::value,
      int32_t, cutlass::layout::TensorNDHWC, 128 /  cutlass::sizeof_bits<int32_t>::value,
      cutlass::epilogue::collective::EpilogueScheduleAuto,
      FusionOperation
    >::CollectiveOp;

  using CollectiveMainloop = typename cutlass::conv::collective::CollectiveBuilder<
      cutlass::arch::Sm100, cutlass::arch::OpClassTensorOp,
      cutlass::conv::Operator::kFprop,
      ElementAct, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementAct),
      ElementFlt, cutlass::layout::TensorNDHWC, 16 / sizeof(ElementFlt),
      ElementAcc,
      MmaTileShape, ClusterShape,
      cutlass::conv::collective::StageCountAutoCarveout<static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))>,
      cutlass::conv::collective::KernelScheduleAuto
    >::CollectiveOp;

  using ProblemShape=cutlass::conv::ConvProblemShape<CollectiveMainloop::DispatchPolicy::ConvOp, CollectiveMainloop::DispatchPolicy::NumSpatialDimensions>; 
  using ConvKernel = cutlass::conv::kernel::ConvUniversal<
      ProblemShape,
      CollectiveMainloop,
      CollectiveEpilogue
    >;

  using Conv = cutlass::conv::device::ConvUniversalAdapter<ConvKernel>;

  EXPECT_TRUE(test::conv::device::TestAllConv<Conv>(2.0f, 1.0f, 0.005f));
}

#endif // defined(CUTLASS_ARCH_MMA_SM100_SUPPORTED) && !defined(CUTLASS_SM100_FAMILY_ARCHS_ENABLED)
