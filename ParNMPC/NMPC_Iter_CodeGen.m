function NMPC_Iter_CodeGen(target,targetLang,DoP)
% target: 'mex' 'lib' 'dll'
% targetLang: 'C' 'C++'
% args: {x0,lambda,mu,u,x,p,LAMBDA}

target     = lower(target);
targetLang = upper(targetLang);

% global variables
global discretizationMethod isMEnabled ...
       uMin uMax xMin xMax GMax GMin ...
       veryBigNum dim N_global
   
% formulate args of NMPC_Iter
N     = N_global;
xDim  = dim.x;
muDim = dim.mu;
uDim  = dim.u;
pDim  = dim.p;

if mod(N,DoP) ~= 0
    error('mod(N,DoP) ~= 0');
else
    segSize = N/DoP;
end

args_x0     = zeros(xDim,1);
args_lambdaSplit = zeros(xDim,  segSize,DoP);
args_muSplit     = zeros(muDim, segSize,DoP);
args_uSplit      = zeros(uDim,  segSize,DoP);
args_xSplit      = zeros(xDim,  segSize,DoP);
args_pSplit      = zeros(pDim,  segSize,DoP);
args_LAMBDASplit = zeros(xDim,xDim,segSize,DoP);
args = {args_x0,...
      args_lambdaSplit,...
      args_muSplit,...
      args_uSplit,...
      args_xSplit,...
      args_pSplit,...
      args_LAMBDASplit};

% config
cfg = coder.config(target);
cfg.FilePartitionMethod = 'SingleFile';

if DoP == 1
    isInParallel = false;
else
    isInParallel = true;
end
cfg.EnableOpenMP = isInParallel;
cfg.TargetLang = targetLang;
stackUsageMax  = (xDim + uDim)*segSize*DoP/360*200000;
cfg.StackUsageMax = stackUsageMax;
cfg.GenerateReport = true;
cfg.DynamicMemoryAllocation = 'off';
%% Generate C/C++ for NMPC_Iter
globalVariable = {'discretizationMethod',coder.Constant(discretizationMethod),...
                  'isMEnabled',coder.Constant(isMEnabled),...
                  'uMax',coder.Constant(uMax),...
                  'uMin',coder.Constant(uMin),...
                  'xMax',coder.Constant(xMax),...
                  'xMin',coder.Constant(xMin),...
                  'GMax',coder.Constant(GMax),...
                  'GMin',coder.Constant(GMin),...
                  'veryBigNum',coder.Constant(veryBigNum)};

if ~strcmp(target,'mex')
    cfg.BuildConfiguration = 'Faster Runs'; % no MexCodeConfig 
    cfg.SupportNonFinite = false; % no MexCodeConfig
    cfg.GenerateExampleMain = 'DoNotGenerate'; % no MexCodeConfig
end

myCCompiler = mex.getCompilerConfigurations(targetLang,'Selected');
switch myCCompiler.Name
    case 'gcc'
        cfg.PostCodeGenCommand = 'buildInfo.addLinkFlags(''-fopenmp'')'; 
    case 'g++'
        cfg.PostCodeGenCommand = 'buildInfo.addLinkFlags(''-fopenmp'')'; 
end

codegen -config cfg ...
         NMPC_Iter ...
         -globals globalVariable...
        -args args