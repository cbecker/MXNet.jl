module TestIO
using MXNet
using Base.Test

using ..Main: rand_dims, reldiff

function test_mnist()
  info("IO::MNIST")
  filenames = mx.get_mnist_ubyte()

  batch_size = 10
  mnist_provider = mx.MNISTProvider(image=filenames[:train_data],
                                    label=filenames[:train_label],
                                    batch_size=batch_size, silent=true, shuffle=false)
  data_spec = mx.provide_data(mnist_provider)
  label_spec = mx.provide_label(mnist_provider)
  @test data_spec == [(:data, (28,28,1,batch_size))]
  @test label_spec == [(:softmax_label, (batch_size,))]

  n_batch = 0
  for batch in mnist_provider
    if n_batch == 0
      data_array  = mx.empty(28,28,1,batch_size)
      label_array = mx.empty(batch_size)
      # have to use "for i=1:1" to get over the legacy "feature" of using
      # [ ] to do concatenation in Julia
      data_targets = [[(1:batch_size, data_array)] for i = 1:1]
      label_targets = [[(1:batch_size, label_array)] for i = 1:1]

      mx.load_data!(batch, data_targets)
      mx.load_label!(batch, label_targets)

      true_labels = [5,0,4,1,9,2,1,3,1,4] # the first 10 labels in MNIST train
      got_labels  = Int[copy(label_array)...]
      @test true_labels == got_labels
    end

    n_batch += 1
  end

  @test n_batch == 60000 / batch_size
end

function test_arrays_impl(data::Vector, label::Vector, provider::mx.ArrayDataProvider)
  data = convert(Vector{Array{Float64}}, data)
  label = convert(Vector{Array{Float64}}, label)

  sample_count = size(data[1])[end]
  batch_size   = mx.get_batch_size(provider)
  idx_all = 1:batch_size:sample_count

  info("IO::Array::#data=$(length(data)),#label=$(length(label)),batch_size=$batch_size")
  for (idx, batch) in zip(idx_all, provider)
    data_batch = [x[[Colon() for i=1:ndims(x)-1]..., idx:min(idx+batch_size-1,sample_count)] for x in data]
    data_get   = [mx.empty(size(x)[1:end-1]..., batch_size) for x in data]
    mx.load_data!(batch, [[(1:batch_size, x)] for x in data_get])

    for (d_real, d_get) in zip(data_batch, data_get)
      @test reldiff(d_real, copy(d_get)[[1:n for n in size(d_real)]...]) < 1e-6
      @test mx.get_pad(batch) == batch_size - size(d_real)[end]
    end
  end
end

function test_arrays()
  sample_count = 15
  batch_size   = 4
  dims_data    = [rand_dims()..., sample_count]
  data         = rand(dims_data...)
  provider     = mx.ArrayDataProvider(data, batch_size=batch_size)
  test_arrays_impl(Array[data], [], provider)

  dims_label   = [rand_dims()..., sample_count]
  label        = rand(dims_label...)
  provider     = mx.ArrayDataProvider(data, label, batch_size=batch_size)
  test_arrays_impl(Array[data], Array[label], provider)

  provider     = mx.ArrayDataProvider(:data=>data, :my_label=>label, batch_size=batch_size)
  test_arrays_impl(Array[data], Array[label], provider)

  dims_data2   = [rand_dims()..., sample_count]
  data2        = rand(dims_data2...)
  provider     = mx.ArrayDataProvider((:data=>data, :data2=>data2), label, batch_size=batch_size)
  test_arrays_impl(Array[data,data2], Array[label], provider)
end

function test_arrays_shuffle()
  info("IO::Array::shuffle")

  sample_count = 15
  batch_size   = 4
  data         = rand(1, sample_count)
  label        = collect(1:sample_count)
  provider     = mx.ArrayDataProvider(data, :index => label, batch_size=batch_size, shuffle=true)

  idx_all      = 1:batch_size:sample_count
  data_got     = similar(data)
  label_got    = similar(label)
  for (idx, batch) in zip(idx_all, provider)
    data_batch  = [(1:batch_size, mx.empty(1,batch_size))]
    label_batch = [(1:batch_size, mx.empty(batch_size))]
    mx.load_data!(batch, typeof(data_batch)[data_batch])
    mx.load_label!(batch, typeof(label_batch)[label_batch])
    data_got[idx:min(idx+batch_size-1,sample_count)] = copy(data_batch[1][2])[1:batch_size-mx.get_pad(batch)]
    label_got[idx:min(idx+batch_size-1,sample_count)] = copy(label_batch[1][2])[1:batch_size-mx.get_pad(batch)]
  end

  @test label_got != label
  @test sort(label_got) == label
  @test reldiff(data_got, data[:,Int[label_got...]]) < 1e-6
end

test_arrays_shuffle()
test_arrays()
test_mnist()

end
