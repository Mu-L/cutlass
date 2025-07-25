/***************************************************************************************************
 * Copyright (c) 2017 - 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
/* \file
   \brief Gemm Profiler
*/

#pragma once

#include <vector>
#include <array>
#include <string>
#include <memory>
#include <algorithm>
#include <unordered_map>

// CUTLASS Library includes
#include "cutlass/library/library.h"
#include "cutlass/library/util.h"
#include "cutlass/library/manifest.h"

// Profiler includes
#include "options.h"
#include "device_context.h"
#include "operation_profiler.h"
#include "performance_result.h"
#include "problem_space.h"
#include "reduction_operation_profiler.h"

/////////////////////////////////////////////////////////////////////////////////////////////////

namespace cutlass {
namespace profiler {

/////////////////////////////////////////////////////////////////////////////////////////////////

/// Abstract base class for each math function
class GemmOperationProfiler : public OperationProfiler {
public:

  /// Problem structure obtained from problem space
  struct GemmProblem {

    cutlass::library::GemmUniversalMode mode{library::GemmUniversalMode::kGemm};

    /// For profiling purposes
    std::vector<gemm::GemmCoord> problem_sizes;
    std::vector<std::array<int64_t, 3>> leading_dims;
    std::vector<std::array<int64_t, 3>> preferred_clusters;
    std::vector<std::array<int64_t, 3>> fallback_clusters;
    std::vector<cutlass::library::RasterOrder> raster_orders;
    std::vector<int> swizzle_sizes;

    int64_t m{16};
    int64_t n{16};
    int64_t k{16};

    
    int cluster_m{1};
    int cluster_n{1};
    int cluster_k{1};
    int cluster_m_fallback{1};
    int cluster_n_fallback{1};
    int cluster_k_fallback{1};
    

    int64_t lda{0};
    int64_t ldb{0};
    int64_t ldc{0};
    std::vector<uint8_t> alpha;
    std::vector<uint8_t> beta;

    cutlass::library::SplitKMode split_k_mode{library::SplitKMode::kNone};
    int split_k_slices{1};
    int batch_count{1};

    cutlass::library::RasterOrder raster_order{cutlass::library::RasterOrder::kHeuristic};
    int swizzle_size{1};
    cutlass::library::RuntimeDatatype runtime_input_datatype_a{};
    cutlass::library::RuntimeDatatype runtime_input_datatype_b{};
    

    // gemm with parallel interleaved reduction
    // gemm epilogue (alpha, beta) = (1.0, 0.0)
    // reduction epilogue (alpha, beta) = (GemmProblem::alpha, GemmProblem::beta)
    std::vector<uint8_t> alpha_one;
    std::vector<uint8_t> beta_zero;

    bool use_pdl{false};

    bool enable_sm90_mixed_dtype_shuffle_test{false};

    //
    // Methods
    //

    /// Parses the problem
    Status parse(
      library::GemmDescription const &operation_desc,
      ProblemSpace const &problem_space,
      ProblemSpace::Problem const &problem);

    int64_t bytes_with_problem_shape(
      library::GemmDescription const &operation_desc,
      gemm::GemmCoord const &problem_shape) const;

    int64_t flops_with_problem_shape(
      library::GemmDescription const &operation_desc,
      gemm::GemmCoord const &problem_shape) const;

    /// Total number of bytes loaded
    int64_t bytes(library::GemmDescription const &operation_desc) const;

    /// Total number of flops computed
    int64_t flops(library::GemmDescription const &operation_desc) const;

    /// Initializes a performance result
    void initialize_result(
      PerformanceResult &result,
      library::GemmDescription const &operation_desc,
      ProblemSpace const &problem_space);
  };

  /// Workspace used
  struct GemmWorkspace {

    DeviceAllocation *A{nullptr};
    DeviceAllocation *B{nullptr};
    DeviceAllocation *C{nullptr};
    DeviceAllocation *Computed{nullptr};
    DeviceAllocation *Reference{nullptr};

    /// Number of copies of the problem workspace which are visited sequentially during
    /// profiling to avoid camping in the last level cache.
    int problem_count{1};

    library::GemmUniversalConfiguration configuration;
    library::GemmUniversalArguments arguments;

    /// Buffer used for the operation's host workspace
    std::vector<uint8_t> host_workspace;

    /// Buffer used for the operations' device workspace
    DeviceAllocation device_workspace;

    /// Library configuration and arguments for reduction operator
    library::ReductionConfiguration reduction_configuration;
    library::ReductionArguments reduction_arguments;

    /// Buffer used for the cutlass reduction operations' host workspace
    std::vector<uint8_t> reduction_host_workspace;

    /// For mixed input dtype kernels
    DeviceAllocation *Scale{nullptr};             // Scale tensor
    DeviceAllocation *Zero{nullptr};              // Zero tensor
    DeviceAllocation *dequantized_AB{nullptr};    // Dequantized A or B tensor for verification
    DeviceAllocation *encoded_AB{nullptr};        // Encoded A or B in int4 x fp8 or shuffle
    DeviceAllocation *packed_Scale{nullptr};      // Packed scale for int4 * fp8

    cudaStream_t stream;
  };

protected:

  //
  // Data members
  //

  /// GEMM problem obtained from problem space
  GemmProblem problem_;

  /// Device memory allocations
  std::vector<GemmWorkspace> gemm_workspace_;

  /// CUTLASS parallel reduction operation to follow this* gemm operation
  library::Operation const *reduction_op_;

public:
  //
  // Methods
  //

  /// Ctor
  GemmOperationProfiler(Options const &options);

  /// Destructor
  virtual ~GemmOperationProfiler();

  GemmProblem const& problem() const { return problem_; }

  /// Prints usage statement for the math function
  virtual void print_usage(std::ostream &out) const;

  /// Prints examples
  virtual void print_examples(std::ostream &out) const;

  /// Extracts the problem dimensions
  virtual Status initialize_configuration(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem);

  /// Initializes workspace
  virtual Status initialize_workspace(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem);

  /// Verifies CUTLASS against references
  virtual bool verify_cutlass(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem);

  /// Measures performance results
  virtual bool profile(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem);

protected:
  /// Update workspace configuration according to flexible user setups
  void update_workspace_(
    GemmWorkspace &gemm_workspace,
    gemm::GemmCoord const &problem_shape,
    std::array<int64_t, 3> const &leading_dim,
    std::array<int64_t, 3> const &preferred_cluster,
    std::array<int64_t, 3> const &fallback_cluster,
    cutlass::library::RasterOrder const &raster_order,
    int swizzle_size,
    bool is_dynamic_cluster_enabled);

  /// Update performance result configuration according to flexible user setups
  void update_result_(
    PerformanceResult &result,
    library::GemmDescription const &operation_desc,
    ProblemSpace const &problem_space,
    gemm::GemmCoord const &problem_shape,
    cutlass::library::RasterOrder const &raster_order,
    std::array<int64_t, 3> const &preferred_cluster,
    std::array<int64_t, 3> const &fallback_cluster,
    int swizzle_size,
    bool is_dynamic_cluster_enabled);

  /// Initializes the performance result
  void initialize_result_(
    PerformanceResult &result,
    Options const &options,
    library::GemmDescription const &operation_desc,
    ProblemSpace const &problem_space);

  /// Verifies CUTLASS against references
  bool verify_with_cublas_(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem,
    GemmWorkspace &gemm_workspace);

  /// Verifies CUTLASS against host and device references
  bool verify_with_reference_(
    Options const &options,
    PerformanceReport &report,
    DeviceContext &device_context,
    library::Operation const *operation,
    ProblemSpace const &problem_space,
    ProblemSpace::Problem const &problem,
    cutlass::library::NumericTypeID element_A,
    cutlass::library::NumericTypeID element_B);

  /// Method to profile a CUTLASS Operation
  Status profile_cutlass_(
    PerformanceResult &result,
    Options const &options,
    library::Operation const *operation,
    void *arguments,
    void *host_workspace,
    void *device_workspace);

  /// Initialize reduction problem dimensions and library::Operation
  bool initialize_reduction_configuration_(
    library::Operation const *operation,
    ProblemSpace::Problem const &problem);
};

/////////////////////////////////////////////////////////////////////////////////////////////////

} // namespace profiler
} // namespace cutlass

/////////////////////////////////////////////////////////////////////////////////////////////////

