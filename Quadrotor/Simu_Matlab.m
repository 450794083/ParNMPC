%% For closed-loop simulation or code generation
function Simu_Matlab
DoP        = 40; % degree of parallism: 1 = in serial, otherwise in parallel
simuLength = 10;
Ts         = 0.01; % sampling interval

simuSteps  = floor(simuLength/Ts);
% Load and init
initData   = coder.load('GEN_initData.mat');
lambdaDim  = initData.lambdaDim;
par        = initData.par;
muDim      = initData.muDim;
uDim       = initData.uDim;
xDim       = initData.xDim;
pDim       = initData.pDim;
N          = initData.N;
x0         = initData.x0;
lambda     = initData.lambda;
mu         = initData.mu;
u          = initData.u;
x          = initData.x;
LAMBDA     = initData.LAMBDA;

% reshape initial guess
sizeSeg     = N/DoP;
lambdaSplit = reshape(lambda,lambdaDim,sizeSeg,DoP);
muSplit     = reshape(mu,    muDim,    sizeSeg,DoP);
uSplit      = reshape(u,     uDim,     sizeSeg,DoP);
xSplit      = reshape(x,     xDim,     sizeSeg,DoP);
pSplit      = reshape(par,   pDim,     sizeSeg,DoP);
LAMBDASplit = reshape(LAMBDA,xDim,xDim,sizeSeg,DoP);

solutionInitialGuess.lambdaSplit = lambdaSplit;
solutionInitialGuess.muSplit     = muSplit;
solutionInitialGuess.uSplit      = uSplit;
solutionInitialGuess.xSplit      = xSplit;
solutionInitialGuess.LAMBDASplit = LAMBDASplit;

options = NMPCSolveOptions();
% options.MaxIterNumTotal = 20;
% options.barrierParaDescentRate = 0.1;
% options.TolEnd   = 1e-5;
% options.barrierParaInit = 0.1;

% define record variables
rec.x       = zeros(simuSteps+1,xDim);
rec.x(1,:)  = x0.';
rec.u       = zeros(simuSteps,uDim);
rec.numIter = zeros(simuSteps,1);
rec.error   = zeros(simuSteps,1);
rec.cost    = zeros(simuSteps,1);
rec.t       = zeros(simuSteps,1);
rec.cpuTime = zeros(simuSteps,1);
%% Simulation

% init
cost        = 0;
RTITimeAll  = 0;

for step = 1:simuSteps %simulation steps
    % Solve the optimal control problem
    [solutionInitialGuess,solutionEnd,output] = NMPC_Solve(x0,pSplit,solutionInitialGuess,options);
    RTITime     = output.timeElapsed;
    iter        = output.iterTotal;
    iterInit    = output.iterInit;
    error       = output.errorEnd;
    % Obtain the first optimal control input
    uOpt = solutionEnd.uSplit(:,1,1);
    
    % System simulation by the 4th-order Explicit Runge-Kutta Method
    pSimVal = zeros(0,1);
    x0 = SIM_Plant_RK4(uOpt(1:4,1),x0,pSimVal,Ts);
    % Update parameters
    if step >= 300 && step <= 305
        pSplit(1,:,:) =  pSplit(1,:,:) + 0.1; % X ref
        pSplit(2,:,:) =  pSplit(2,:,:) - 0.1; % Y ref
        pSplit(3,:,:) =  pSplit(3,:,:) + 0.1; % Z ref
    elseif step >= 600 && step <= 610
        pSplit(1,:,:) = pSplit(1,:,:)  - 0.1; % X ref
        pSplit(2,:,:) = pSplit(2,:,:)  + 0.1; % Y ref
        pSplit(3,:,:) = pSplit(3,:,:)  - 0.1; % Z ref
    end

    % Record data
    rec.x(step+1,:)      = x0.';
    rec.u(step,:)        = uOpt.';
    rec.error(step,:)    = error;
    rec.cpuTime(step,:)  = RTITime*1e6;
    rec.t(step,:)        = step*Ts;
    rec.numIter(step,:)  = iter;
    rec.cost(step,:)     = cost;
    if coder.target('MATLAB')
         disp(['Step: ',num2str(step),'/',num2str(simuSteps),...
               '   iterInit: ',num2str(iterInit),...
               '   iterTotal: ',num2str(iter),...
               '   error:' ,num2str(error)]);
    end
end
%% Log to file
if coder.target('MATLAB')% Normal excution
    save('GEN_log_rec.mat','rec');
    % count time
    disp(['Time Elapsed for RTI: ',num2str(RTITimeAll) ' seconds ']);
else % Code generation
    coder.cinclude('stdio.h');
    coder.cinclude('omp.h');
    % show Time Elapsed for RTI
    fmt1 = coder.opaque( 'const char *',['"',...
                                        'Time Elapsed for RTI (Real Time Iteration): %f s\r\n',...
                                        'Timer Precision: %f us\r\n',...
                                        '"']);
    wtrick = 0; % Timer precision
    wtrick = coder.ceval('omp_get_wtick');
    wtrick = wtrick*1e6;
    coder.ceval('printf',fmt1, RTITimeAll,wtrick);
    % Log to file
    fileID = fopen('GEN_log_rec.txt','w');
    % printf header
    for j=1:xDim
        fprintf(fileID,'%s\t',['x',char(48+j)]);
    end
    for j=1:uDim
        fprintf(fileID,'%s\t',['u',char(48+j)]);
    end
    fprintf(fileID,'%s\t','error');
    fprintf(fileID,'%s\t','numIter');
    fprintf(fileID,'%s\n','cpuTime');
    % printf data
    for i=1:simuSteps
        for j=1:xDim
            fprintf(fileID,'%f\t',rec.x(i,j));
        end
        for j=1:uDim
            fprintf(fileID,'%f\t',rec.u(i,j));
        end
        fprintf(fileID,'%f\t',rec.error(i,1));
        fprintf(fileID,'%f\t',rec.numIter(i,1));
        fprintf(fileID,'%f\n',rec.cpuTime(i,1));
    end
    fclose(fileID);
end