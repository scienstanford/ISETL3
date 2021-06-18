%% t_L3SuperResolution
%
% Explore the super resolution based on L3 approach. The idea is change the
% pixel size according to the upscale factor. In this way, we can adjust
% the resolution of the sensor and thus the resolution of the final image.
%
% SR:  Super resolution
%
% Zheng Lyu, BW 2019

%% Initiation
ieInit;
%% Set the destination folder

dFolder = fullfile(L3rootpath,'local','scenes');
%% Download the scene from RDT
% rdt = RdtClient('scien');
% rdt.readArtifacts('/L3/quad/scenes','destinationFolder',dFolder);

%% Load the scenes. Here we have 22 scenes from the COCO dataset.
% Common objects in context.

format = 'mat';
scenes = loadScenes(dFolder, format, 1:22);
% scenes{3} = sceneCreate('uniform'); 
% scenes{1} = sceneSet(scenes{1}, 'fov', 15);
% scenes{2} = sceneSet(scenes{2}, 'fov', 15);

%% Use l3DataSimulation to generate raw and desired RGB image

% 
l3dSR = l3DataSuperResolution();

% Some other scene options for evaluation
% sceneSampleOne = sceneSet(sceneCreate, 'fov', 12);
% sceneSampleTwo = sceneSet(sceneCreate('sweep'))

% Take the first scene for training.
l3dSR.sources = scenes(1:10);

% Set the upscale factor to be 3
l3dSR.upscaleFactor = 2;
%% Adjust the settings of the camera
camera = l3dSR.camera;

% Let's try to use this instead:
% 
sensor = cameraGet(camera,'sensor');
% sensor = sensorSet(sensor, 'pixel size', 1.5e-6);
fillFactor = 1;
sensor = pixelCenterFillPD(sensor,fillFactor);

camera = cameraSet(camera,'sensor',sensor);

% data = load('NikonD100Sensor.mat', 'isa'); sensor = data.isa;
% camera = cameraSet(camera, 'sensor', sensor);
% The default photodetector position has an offset.  We should look
% into this generally for ISETCam.
% camera = cameraSet(camera, 'pixel pdXpos', 0);
% camera = cameraSet(camera, 'pixel pdYpos', 0);
% 
% % set the fill factor to be 1
% pixelSize  = cameraGet(camera, 'pixel size');
% camera = cameraSet(camera, 'pixel pdWidth', pixelSize(1));
% camera = cameraSet(camera, 'pixel pdHeight', pixelSize(2));

% Give the camera back to the L3 data instance.
l3dSR.camera = camera;
%% Specify the super-resolution classifier

l3tSuperResolution = l3TrainRidge('l3c', l3ClassifySR);

%% Set the parameters for the L3 training instance

% Calculate the number of the saturation conditions. For every
% possible saturation case, 2^numel(CFA positions), we have a
% saturation class. So we have one less cutpoint to separate them. So,
% if there are 4 CFA positions, we have 2^4 saturation possibilities
% and 2^4 - 1 cutpoints.
%
% The main case is when none of the CFA positions are saturated.
nSatSituation = (1:(2^numel(l3dSR.cfa) - 1));

% Set up the cut pointsl  The first term is with respect to the
% voltage swing.  The second terms is for contrast.  The third is for
% saturation classes.
l3tSuperResolution.l3c.cutPoints = {logspace(-1.7, -0.12, 30),...
                                        [], nSatSituation};
                                    
% Set the size of the patch                                    
l3tSuperResolution.l3c.patchSize = [9 9];
l3tSuperResolution.l3c.numMethod = 2;

% Add this line to change the size of the SR target patches
l3tSuperResolution.l3c.srPatchSize = [7 7] * l3dSR.upscaleFactor;

%% Invoke the training algorithm

% By default, the training algorithm uses least squares.  We will add
% other minimization training algorithms in the future.dnpu-
l3tSuperResolution.train(l3dSR);

%{
% Save the trained model
modelName = 'L3DirectXYZ.mat'; modelTimedName = strcat(date, modelName);
save(fullfile(L3rootpath, 'local', 'saved_model', modelTimedName), 'l3tSuperResolution','-v7.3');
%}


%% Evaluation process. 

%{
thisKernel = 100;
kernel  = l3tSuperResolution.kernels{thisKernel};
[X, y] =l3tSuperResolution.l3c.getClassData(thisKernel); 
X = padarray(X, [0 1], 1, 'pre');
y_fit = X * kernel;
thisChannel = 10;
plot(y_fit(:,thisChannel), y(:,thisChannel), 'o');
axis square; 
identityLine;
%}

cList = 10:20:100
% How many classes have fewer than 10 examples?
% How many kernels are empty?
kernels = l3tSuperResolution.kernels;
emptyKernels  = cellfun(@(x)(isempty(x)),kernels);
filledKernels = 1 - emptyKernels;
fprintf('Empty kernels: %d\nFilled kernels %d\n',sum(emptyKernels), sum(filledKernels));

% The kernel number is calculated from
%
%     trainClass = (thisSatCondition-1)*nPixelTypes*allSignalMean + ...
%        (thisLevel - 1)*nPixelTypes + ...
%        thisCenterPixel;
%
%   
% From a kernel number, can we figure out the class, center pixel,
% saturation condition? Look at some of the filledKernels
%
% Show the empty classes
% ieNewGraphWin; plot(1:length(validClass),validClass)

% Choose a level less than this
%   nLevels = numel(l3tSuperResolution.l3c.cutPoints{1})
thisLevel = 6; thisCenterPixel = 4; thisSatCondition = 1;
thisOutChannel = 1;
[X, y_pred, y_true] = checkLinearFit(l3tSuperResolution, thisLevel,...
    thisCenterPixel, thisSatCondition, thisOutChannel, l3dSR.cfa,...
    l3dSR.upscaleFactor);

%% Simulate the HR image
% Set a test scene
thisScene = 5;
source = scenes{thisScene};
% sceneWindow(source);

% Other options for evaluation
% source = sceneCreate;
% source = sceneCreate('uniform');
% source = sceneCreate('rings rays');
% source = sceneCreate('sweep frequency');

% Converte the source to optical image if input is a scene.
switch source.type
    case 'scene'
        oi = cameraGet(l3dSR.camera, 'oi');
        oi = oiCompute(oi, source);
        oiSource = oi;
    case 'opticalimage'
        oiSource = source;
end
% oiWindow(oiSource);



% Get the sensor from the camera
sensor = cameraGet(l3dSR.camera, 'sensor');

% Set the noise free sensor
sensorNF = sensorSet(sensor, 'noise flag', -1);

% Adjust the pixel size, but keep the same fill factor
sensorNF = sensorSet(sensorNF, 'pixel size same fill factor',...
    sensorGet(sensor, 'pixel size')/l3dSR.upscaleFactor); % Change the pixel size

sensorNF = sensorSet(sensorNF, 'size', sensorGet(sensor, 'size') * l3dSR.upscaleFactor);
sensorNF = sensorSet(sensorNF, 'expTime',1);
idealCF = l3dSR.get('ideal cmf');  idealCF = idealCF./ max(max(max(idealCF)));
hrImg = xyz2srgb(sensorComputeFullArray(sensorNF, oiSource, idealCF));
ieNewGraphWin; imshow(hrImg);
%{
    % Use these commands when outImg is L3 rendered sensor data 

    sensorHR = sensorSet(sensor,'pixel size', ...
                sensorGet(sensor, 'pixel size') / l3dSR.upscaleFactor);
    sensorHR = sensorSet(sensorHR, 'size', ...
                sensorGet(sensor, 'size') * l3dSR.upscaleFactor);

    switch source.type
        case 'scene'
            oi = cameraGet(l3dSR.camera, 'oi');
            oi = oiCompute(oi, source);
            sensorHR = sensorCompute(sensorHR, oi);
        case 'opticalimage'
            sensorHR = sensorCompute(sensorHR, source);
    end   
    ipHR = cameraGet(l3dSR.camera, 'ip');
    ipHR = ipCompute(ipHR, sensorHR);
    hrImg = ipGet(ipHR, 'data srgb');
    % ieNewGraphWin; imshow(hrImg);
%}

%% Render a scene to evaluate the training result
l3rSR = l3RenderSR();
% sensor = sensorSet(sensor, 'noise flag', -1);
% Generate the LR sensor data
sensor = sensorSetSizeToFOV(sensor, oiGet(oiSource, 'fov'));
sensor = sensorCompute(sensor, oiSource);

% sensorWindow(sensor);
cfa     = cameraGet(l3dSR.camera, 'sensor cfa pattern');
cmosaic = sensorGet(sensor, 'volts');

% Get the ip for the low resolution
ipLR = cameraGet(l3dSR.camera, 'ip');
ipLR = ipCompute(ipLR, sensor);
lrImg = ipGet(ipLR, 'data srgb');
% ipWindow(ipLR);

% Compute L3 rendered image
outImg = l3rSR.render(cmosaic, cfa, l3tSuperResolution, l3dSR);

% Use this command when outImg is XYZ image
ieNewGraphWin; l3SR = xyz2srgb(outImg); imshow(l3SR);


%{
    % Use these commands when outImg is L3 rendered sensor data
    sensorSR = sensorSet(sensor, 'pixel size same fill factor',...
        sensorGet(sensor, 'pixel size')/l3dSR.upscaleFactor); % Change the pixel size
    sensorSR = sensorSet(sensorSR, 'volts', outImg);
    sensorSR = sensorSet(sensorSR, 'digital value',...
                    analog2digital(sensorSR, 'linear'));
    ipSR = ipCreate;
    ipSR = ipCompute(ipSR, sensorSR);
    ipWindow(ipSR)
    l3SR = ipGet(ipSR, 'data srgb');
%}

%% Plot the result
ieNewGraphWin;
subplot(1, 3, 1); imshow(lrImg); title('low resolution img using IP');
subplot(1, 3, 2); imshow(hrImg); title('high resolution img using xyz2srgb');
subplot(1, 3, 3); imshow(l3SR); title('l3 rendered img using xyz2srgb');

%% END