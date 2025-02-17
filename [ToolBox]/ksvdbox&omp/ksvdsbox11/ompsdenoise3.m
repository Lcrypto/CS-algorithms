function [y,nz] = ompsdenoise3(params,msgdelta)
%OMPSDENOISE3 Sparse OMP denoising of 3-D signals.
%  OMPSDENOISE3 denoises a 3-dimensional signal using Sparse OMP denoising.
%  The function syntax is identical to OMPSDENOISE, but it runs
%  significantly faster on 3-D signals. OMPSDENOISE3 requires somewhat more
%  memory than OMPSDENOISE (approximately the size of the input signal), so
%  if memory is limited, OMPSDENOISE can be used instead.
%
%  See also OMPSDENOISE.


%  Ron Rubinstein
%  Computer Science Department
%  Technion, Haifa 32000 Israel
%  ronrubin@cs
%
%  August 2009


% parse input arguments %

x = params.x;
basedict = params.basedict;
A = params.A;
blocksize = params.blocksize;


% blocksize %
if (numel(blocksize)==1)
  blocksize = ones(1,3)*blocksize;
end


% maxval %
if (isfield(params,'maxval'))
  maxval = params.maxval;
else
  maxval = 1;
end


% gain %
if (isfield(params,'gain'))
  gain = params.gain;
else
  gain = 1.15;
end


% maxatoms %
if (isfield(params,'maxatoms'))
  maxatoms = params.maxatoms;
else
  maxatoms = floor(prod(blocksize)/2);
end


% stepsize %
if (isfield(params,'stepsize'))
  stepsize = params.stepsize;
  if (numel(stepsize)==1)
    stepsize = ones(1,3)*stepsize;
  end
else
  stepsize = ones(1,3);
end
if (any(stepsize<1))
  error('Invalid step size.');
end


% noise mode %
if (isfield(params,'noisemode'))
  switch lower(params.noisemode)
    case 'psnr'
      sigma = maxval / 10^(params.psnr/20);
    case 'sigma'
      sigma = params.sigma;
    otherwise
      error('Invalid noise mode specified');
  end
elseif (isfield(params,'sigma'))
  sigma = params.sigma;
elseif (isfield(params,'psnr'))
  sigma = maxval / 10^(params.psnr/20);
else
  error('Noise strength not specified');
end


% lambda %
if (isfield(params,'lambda'))
  lambda = params.lambda;
else
  lambda = maxval/(10*sigma);
end


% msgdelta %
if (nargin <2)
  msgdelta = 5;
end
if (msgdelta<=0)
  msgdelta = -1;
end


epsilon = sqrt(prod(blocksize)) * sigma * gain;   % target error for omp


MEM_LOW = 1;
MEM_NORMAL = 2;
MEM_HIGH = 3;

if (isfield(params,'memusage'))
  switch lower(params.memusage)
    case 'low'
      memusage = MEM_LOW;
    case 'normal'
      memusage = MEM_NORMAL;
    case 'high'
      memusage = MEM_HIGH;
    otherwise
      error('Invalid memory usage mode');
  end
else
  memusage = MEM_NORMAL;
end


% compute G %

G = [];
if (memusage >= MEM_NORMAL)
  G = dicttsep(basedict,A,dictsep(basedict,A,speye(size(A,2))));
end


% verify dictionary normalization %

if (isempty(G))
  atomnorms = zeros(1,size(A,2));
  gamma = speye(size(A,2));
  for i = 1:size(A,2)
    atomnorms(i) = sum(dictsep(basedict,A,gamma(:,i)).^2);
  end
else
  atomnorms = diag(G);
end
if (any(abs(atomnorms-1) > 1e-2))
  error('Dictionary atoms are not normalized to unit length');
end


% denoise the signal %

nz = 0;  % count non-zeros in block representations

% the denoised signal
y = zeros(size(x));

blocknum = prod(floor((size(x)-blocksize)./stepsize) + 1);
processedblocks = 0;
tid = timerinit('ompsdenoise', blocknum);

for k = 1:stepsize(3):size(y,3)-blocksize(3)+1
  for j = 1:stepsize(2):size(y,2)-blocksize(2)+1
    
    % the current batch of blocks
    blocks = im2colstep(x(:,j:j+blocksize(2)-1,k:k+blocksize(3)-1),blocksize,stepsize);

    % remove DC
    [blocks, dc] = remove_dc(blocks,'columns');

    % denoise the blocks
    gamma = omps2(basedict,A,blocks,G,epsilon,'maxatoms',maxatoms,'checkdict','off');
    nz = nz + nnz(gamma);
    cleanblocks = add_dc(dictsep(basedict,A,gamma), dc, 'columns');
    
    cleanvol = col2imstep(cleanblocks,[size(y,1) blocksize(2:3)],blocksize,stepsize);
    y(:,j:j+blocksize(2)-1,k:k+blocksize(3)-1) = y(:,j:j+blocksize(2)-1,k:k+blocksize(3)-1) + cleanvol;
    
    if (msgdelta>0)
      processedblocks = processedblocks + size(blocks,2);
      timereta(tid, processedblocks, msgdelta);
    end
    
  end
end

if (msgdelta>0)
  timereta(tid, blocknum);
end


nz = nz/blocknum;  % average number of non-zeros

% average the denoised and noisy signals
cnt = countcover(size(x),blocksize,stepsize);
y = (y+lambda*x)./(cnt + lambda);

