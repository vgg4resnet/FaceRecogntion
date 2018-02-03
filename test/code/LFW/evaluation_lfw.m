% --------------------------------------------------------
% Copyright (c) Weiyang Liu, Yandong Wen
% Licensed under The MIT License [see LICENSE for details]
%
% Intro:
% This script is used to evaluate the performance of the trained model on LFW dataset.
% We perform 10-fold cross validation, using cosine similarity as metric.
% More details about the testing protocol can be found at http://vis-www.cs.umass.edu/lfw/#views.
% 
% Usage:
% cd $SPHEREFACE_ROOT/test
% run code/evaluation.m
% --------------------------------------------------------

function evaluation_lfw()

clear;clc;close all;
%cd('../')

%% caffe setttings
matCaffe = '/home/zf/deeplearning/caffe/matlab';
addpath(matCaffe);
gpu = true;
if gpu
   gpu_id = 1;
   caffe.set_mode_gpu();
   caffe.set_device(gpu_id);
else
   caffe.set_mode_cpu();
end
caffe.reset_all();

model   = '/home/zf/deeplearning/caffe/face_example/face-recognition/AMSoftmax/ms_1m/face_deploy.prototxt';
weights = '/home/zf/deeplearning/caffe/face_example/face-recognition/AMSoftmax/ms_1m/face_snapshot/ms1m_train_test_iter_120000.caffemodel';
net     = caffe.Net(model, weights, 'test');
%net.save('result/sphereface_model.caffemodel');

% load pairs_amsoftmax_param.mat
%% compute features

pairs = parseList('/data/pairs.txt', '/data/lfw-112X96');
for i = 1:length(pairs)
    fprintf('extracting deep features from the %dth face pair...\n', i);
    pairs(i).featureL = extractDeepFeature(pairs(i).fileL, net);
    pairs(i).featureR = extractDeepFeature(pairs(i).fileR, net);
end
%save pairs_amsoftmax_ms_1m.mat pairs

%% 10-fold evaluation
pairs = struct2cell(pairs')';
ACCs  = zeros(10, 1);
fprintf('\n\n\nfold\tACC\n');
fprintf('----------------\n');
for i = 1:10
    fold      = cell2mat(pairs(:, 3));
    flags     = cell2mat(pairs(:, 4));
    featureLs = cell2mat(pairs(:, 5)');
    featureRs = cell2mat(pairs(:, 6)');

    % split 10 folds into val & test set
    valFold   = find(fold~=i);
    testFold  = find(fold==i);

    % get normalized feature
    mu        = mean([featureLs(:, valFold), featureRs(:, valFold)], 2);
    featureLs = bsxfun(@minus, featureLs, mu);
    featureRs = bsxfun(@minus, featureRs, mu);
    featureLs = bsxfun(@rdivide, featureLs, sqrt(sum(featureLs.^2)));
    featureRs = bsxfun(@rdivide, featureRs, sqrt(sum(featureRs.^2)));

    % get accuracy of the ith fold using cosine similarity
    scores    = sum(featureLs .* featureRs);
    threshold = getThreshold(scores(valFold), flags(valFold), 10000);
    ACCs(i)   = getAccuracy(scores(testFold), flags(testFold), threshold);
    fprintf('%d\t%2.2f%%\n', i, ACCs(i)*100);
end
fprintf('----------------\n');
fprintf('AVE\t%2.2f%%\n', mean(ACCs)*100);

rocCurve(cell2mat(pairs(:, 5)'),cell2mat(pairs(:, 6)'),cell2mat(pairs(:, 4)));

end

function rocCurve(featureLs,featureRs,label)
    mu        = mean([featureLs, featureRs], 2);
    featureLs = bsxfun(@minus, featureLs, mu);
    featureRs = bsxfun(@minus, featureRs, mu);
    featureLs = bsxfun(@rdivide, featureLs, sqrt(sum(featureLs.^2)));
    featureRs = bsxfun(@rdivide, featureRs, sqrt(sum(featureRs.^2)));
    scores    = sum(featureLs .* featureRs);
    thresh = sort(scores);
    Nthresh = length(thresh);
    hitRate = zeros(1, Nthresh);
    rec = zeros(1,Nthresh);
    faRate = zeros(1, Nthresh);
    class1 = find(label==1);
    class0 = find(label==-1);
    
    for i =1:Nthresh
        th = thresh(i);
        % hit rate = TP/P
        hitRate(i) = sum(scores(class1) >= th) / length(class1);
        % fa rate = FP/N
        faRate(i) = sum(scores(class0) >= th) / length(class0);
        rec(i) =  (sum(scores(class1) >= th) + sum(scores(class0) < th)) / Nthresh;
    end
    AUC = sum(abs(faRate(2:end) - faRate(1:end-1)) .* hitRate(2:end));
    i1 = find(hitRate >= (1-faRate), 1, 'last' ) ;
    i2 = find((1-faRate) >= hitRate, 1, 'last' ) ;
    EER = 1 - max(1-faRate(i1), hitRate(i2)) ;
    [ACC,index]= max(rec);
    best_threshold = thresh(index)
    
    loglog(faRate, hitRate, '-');
    xlabel('False Positiucve Rate')
    ylabel('True Positive Rate')
    grid on
    title(sprintf('Acc = %5.4f,AUC = %5.4f, EER = %5.4f',ACC, AUC, EER));
    
end


function pairs = parseList(list, folder)
    i    = 0;
    fid  = fopen(list);
    line = fgets(fid);
    while ischar(line)
          strings = strsplit(line, '\t');
          if length(strings) == 3
             i = i + 1;
             pairs(i).fileL = fullfile(folder, strings{1}, [strings{1}, num2str(str2num(strings{2}), '_%04i.jpg')]);
             pairs(i).fileR = fullfile(folder, strings{1}, [strings{1}, num2str(str2num(strings{3}), '_%04i.jpg')]);
             pairs(i).fold  = ceil(i / 600);
             pairs(i).flag  = 1;
          elseif length(strings) == 4
             i = i + 1;
             pairs(i).fileL = fullfile(folder, strings{1}, [strings{1}, num2str(str2num(strings{2}), '_%04i.jpg')]);
             pairs(i).fileR = fullfile(folder, strings{3}, [strings{3}, num2str(str2num(strings{4}), '_%04i.jpg')]);
             pairs(i).fold  = ceil(i / 600);
             pairs(i).flag  = -1;
          end
          line = fgets(fid);
    end
    fclose(fid);
end

function feature = extractDeepFeature(file, net)
    img     = single(imread(file));
    img     = (img - 127.5)/128;
    img     = permute(img, [2,1,3]);
    img     = img(:,:,[3,2,1]);
    res     = net.forward({img});
    res_    = net.forward({flip(img, 1)});
    feature = double([res{1}; res_{1}]);
end

function bestThreshold = getThreshold(scores, flags, thrNum)
    accuracys  = zeros(2*thrNum+1, 1);
    thresholds = (-thrNum:thrNum) / thrNum;
    for i = 1:2*thrNum+1
        accuracys(i) = getAccuracy(scores, flags, thresholds(i));
    end
    bestThreshold = mean(thresholds(accuracys==max(accuracys)));
end

function accuracy = getAccuracy(scores, flags, threshold)
    accuracy = (length(find(scores(flags==1)>threshold)) + ...
                length(find(scores(flags~=1)<threshold))) / length(scores);
end