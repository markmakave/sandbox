#pragma once

#include <cuda_runtime.h>
#include "cuda/matrix.cuh"
#include "base/color.hpp"

namespace lm {
namespace cuda {

__global__
void
detect(matrix<lm::gray> input, matrix<bool> output);

__global__
void
test(int, int, int);

}
}
