/* 

    Copyright (c) 2023 Mark Mokhov

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

*/

#pragma once

#include "base/types.hpp"
#include "base/tensor.hpp"
#include "cuda/memory.cuh"

#include <cuda_runtime.h>

namespace lm {
namespace cuda {

template <i32 N>
struct shape_t
{
public:

    using size_type = i64;

public:

    __host__ __device__
    shape_t()
    :   _data{}
    {}

    template <typename... Size>
    __host__ __device__
    shape_t(Size ...sizes)
    :   _data{static_cast<size_type>(sizes)...}
    {
        static_assert(sizeof...(Size) == N);
    }

    __host__ __device__
    shape_t(const shape_t& s)
    {
        for (i32 n = 0; n < N; ++n)
            _data[n] = s._data[n];
    }

    __host__
    shape_t (const lm::shape_t<N>& s)
    {
        for (i32 n = 0; n < N; ++n)
            (*this)[n] = s[n];
    }

    __host__ __device__
    shape_t&
    operator = (const shape_t& s)
    {
        for (i32 n = 0; n < N; ++n)
            _data[n] = s._data[n];
        return *this;
    }

    __host__ __device__
    bool
    operator == (const shape_t& s) const
    {
        for (i32 n = 0; n < N; ++n)
            if (_data[n] != s[n])
                return false;
        return true;
    }

    __host__ __device__
    bool
    operator != (const shape_t& s) const
    {
        return !((*this) == s);
    }

    __host__ __device__
    size_type&
    operator [] (size_type dim)
    {
        return _data[dim];
    }

    __host__ __device__
    size_type
    operator [] (size_type dim) const
    {
        return _data[dim];
    }

    __host__
    operator lm::shape_t<N> () const
    {
        shape_t<N> s;
        for (i32 n = 0; n < N; ++n)
            s[n] = (*this)[n];
        return s;
    }

private:

    size_type _data[N];
};

template <i32 N, typename T, typename _alloc>
class tensor
{
public:

    using value_type        = T;
    using pointer           = value_type*;
    using const_pointer     = const value_type*;
    using reference         = value_type&;
    using const_reference   = const value_type&;
    using iterator          = pointer;
    using const_iterator    = const_pointer;
    using shape_type        = shape_t<N>;
    using size_type         = typename shape_type::size_type;

public:

    __host__ __device__
    tensor()
    :   _data(nullptr),
        _shape()
    {}
    
    template <typename... Size>
    __host__ __device__
    tensor(Size ...sizes)
    :   _data(nullptr),
        _shape()
    {
        reshape(sizes...);
    }

    __host__ __device__
    tensor(const shape_type& shape)
    :   _data(nullptr),
        _shape()
    {
        reshape(shape);
    }

    __host__ __device__
    tensor(const tensor& t)
    :   _data(nullptr),
        _shape()
    {
        reshape(t.shape());
        _alloc::copy(t._data, _data, size()); 
    }

    __host__ __device__
    tensor(tensor&& t)
    :   _data(t._data),
        _shape(t._shape)
    {
        t._data = nullptr;
        t._shape = shape_type();
    }

    __host__ __device__
    ~tensor()
    {
        _deallocate();
    }

    __host__ __device__
    tensor&
    operator = (const tensor& t)
    {
        if (&t != this)
        {
            reshape(t._shape);
            _alloc::copy(t._data, _data, t.size() * sizeof(value_type));
        }

        return *this;
    }

    __host__ __device__
    tensor&
    operator = (tensor&& t)
    {
        if (&t != this)
        {
            _data = t._data;
            _shape = t._shape;

            t._data = nullptr;
            t._shape = shape_type();
        }

        return *this;
    }

    template <typename U, typename alloc>
    __host__ __device__
    tensor&
    operator = (const tensor<N, U, alloc>& t)
    {
        reshape(t.shape());
        for (size_type i = 0; i < t.size(); ++i)
            _alloc::access(_data + i) = static_cast<value_type>(t.data()[i]);

        return *this;
    }

    __host__ __device__
    void
    fill(const_reference fillament)
    {
        for (size_type i = 0; i < size(); ++i)
            _alloc::access(_data + i) = fillament;

    }

    __host__ __device__
    const shape_type&
    shape() const
    {
        return _shape;
    }

    __host__ __device__
    pointer
    data()
    {
        return _data;
    }

    __host__ __device__
    const_pointer
    data() const
    {
        return _data;
    }

    __host__ __device__
    size_type
    size() const
    {
        size_type s = 1;
        for (size_type n = 0; n < N; ++n)
            s *= _shape[n];
        return s;
    }

    template <typename... Size>
    __host__ __device__
    void
    reshape(Size ...sizes)
    {
        static_assert(sizeof...(Size) == N);

        shape_type new_shape(sizes...);
        reshape(new_shape);
    }

    __host__ __device__
    void
    reshape(const shape_type& shape)
    {
        if (_shape == shape)
            return;

        _deallocate();
        _shape = shape;
        _allocate();
    }

    __host__ __device__
    decltype(auto)
    operator () (size_type indices[N])
    {
        size_type offset = 0;
        size_type dim = 1;
        for (size_type n = 0; n < N; ++n)
        {
            offset += dim * indices[n];
            dim *= _shape[n];
        }

        return _alloc::access(_data + offset);
    }

    __host__ __device__
    decltype(auto)
    operator () (size_type indices[N]) const
    {
        size_type offset = 0;
        size_type dim = 1;
        for (size_type n = 0; n < N; ++n)
        {
            offset += dim * indices[n];
            dim *= _shape[n];
        }

        return _alloc::access(_data + offset);
    }

    template <typename... Index>
    __host__ __device__
    decltype(auto)
    operator () (Index ...index)
    {
        static_assert(sizeof...(Index) == N);

        size_type indices[N] = {index...};

        return (*this)(indices);
    }

    template <typename... Index>
    __host__ __device__
    decltype(auto)
    operator () (Index ...index) const
    {
        static_assert(sizeof...(Index) == N);

        size_type indices[N] = {index...};

        return (*this)(indices);
    }

    #if __cplusplus >= 202002L

    template <typename... Index>
    __host__ __device__
    decltype(auto)
    operator [] (Index ...index)
    {
        return operator()(index...);
    }

    template <typename... Index>
    __host__ __device__
    decltype(auto)
    operator [] (Index ...index) const
    {
        return operator()(index...);
    }

    #endif

    template <typename alloc>
    __host__
    void
    operator << (const lm::tensor<N, value_type, alloc>& t)
    {
        reshape(t.shape());
        // _alloc::copy(t.data(), _data, t.size(), memcpy_kind::H2D);
        memcpy(_data, t.data(), t.size() * sizeof(value_type), memcpy_kind::H2D);
    }

    template <typename alloc>
    __host__
    void
    operator >> (lm::tensor<N, value_type, alloc>& t) const
    {
        t.reshape(_shape);
        // _alloc::copy(_data, t.data(), size(), memcpy_kind::D2H);
        memcpy(t.data(), _data, size() * sizeof(value_type), memcpy_kind::D2H);
    }

protected:

    pointer   _data;
    shape_type _shape;

protected:

    __host__ __device__
    void
    _allocate()
    {
        _data = _alloc::allocate(size());
    }

    __host__ __device__
    void
    _deallocate()
    {
        _alloc::deallocate(_data);
    }
};

}
}
