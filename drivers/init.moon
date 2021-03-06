require 'cunn'
_ = require 'moses'

import dofile from require 'moonscript'
import thisfile from require 'paths'

dofile(thisfile 'MaskedCrossEntropyCriterion.moon')
dofile(thisfile 'SIPCriterion.moon')

init = (model, workers, opts) ->
  crit = nn.SIPCriterion(nn.MaskedCrossEntropyCriterion!)
  if opts.decoding == ''
    crit = with nn.ParallelCriterion!
      \add crit
      \add crit\clone!

  state = _.defaults opts.savedState or {},
      t: 0
      crit: crit\cuda!

  gpuSents = torch.CudaTensor(opts.batchSize, opts.sentlen)
  state.gpuSents = gpuSents
  if opts.decoding ~= ''
    state.prepBatch = (batchSents) ->
      gpuSents\resize(batchSents\size!)\copy(batchSents)
      sentlen = batchSents\size(2) - 1
      encSents = gpuSents\narrow(2, 2, sentlen)
      {encSents, gpuSents\narrow(2, 1, sentlen)}, encSents
  else
    gpuNextSents = torch.CudaTensor(opts.batchSize, opts.sentlen)
    gpuPrevSents = torch.CudaTensor(opts.batchSize, opts.sentlen)

    state.prepBatch = (batchSents, batchPrevSents, batchNextSents) ->
      gpuSents\resize(batchSents\size!)\copy(batchSents)
      gpuPrevSents\resize(batchPrevSents\size!)\copy(batchPrevSents)
      gpuNextSents\resize(batchNextSents\size!)\copy(batchNextSents)

      input = {gpuSents, gpuPrevSents[{{}, {1, -2}}], gpuNextSents[{{}, {1, -2}}]}
      target = {gpuPrevSents[{{}, {2, -1}}], gpuNextSents[{{}, {2, -1}}]}

      input, target

    state.gpuPrevSents = gpuPrevSents
    state.gpuNextSents = gpuNextSents


  drivers = {}
  lazyDrivers = {}

  for i, driver in pairs {'train', 'val', 'snap'}
    drivers[i] = (...) -> lazyDrivers[i](...)
    lazyDrivers[i] = (...) ->
      lazyDrivers[i] = dofile(thisfile driver..'.moon')(model, workers, opts, state)
      lazyDrivers[i](...)

  table.unpack drivers

{ :init }
