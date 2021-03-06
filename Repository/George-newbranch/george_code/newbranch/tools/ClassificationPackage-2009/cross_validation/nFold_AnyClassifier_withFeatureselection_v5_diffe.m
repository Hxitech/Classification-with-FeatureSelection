% v5 can use balanced train set in CV
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Input:
%   data_set: data
%   data_labels: labels
%   feature_list: the feature name list in cell
%   para:
%    parameter like what classifier you use, the number of top feature
%    para.classifier='LDA';
%    para.num_top_feature=5;
%    para.featureranking='wilcoxon';
%    para.correlation_factor=.9;
%   shuffle: 1 for random, 0 for non-random partition (Default: 1)
%   n: Number of folds to your cross-validation (Default: 3)
%   nIter: Number of cross-validation iterations (Default: 1)
%   Subsets: pass your own training and testing subsets & labels (Default:
%   computer will generate using 'nFold')
%
% Output:
%   stats: struct containing TP, FP, TN, FN, etc.
%   The function is written by Cheng Lu @2016
%   example here:
% para.balanced_trainset=1;
% para.get_balance_sens_spec=1;
% para.feature_score_method='weighted';
% para.classifier='BaggedC45';
% para.num_top_feature=6;
% para.featureranking='wilcoxon';
% para.correlation_factor=.99;
% [resultImbalancedC45,feat_scores] = nFold_AnyClassifier_withFeatureselection_v5(data_cLoCoM_train_truncated_583(label_SC_AD,:),double(label_KRAS(label_SC_AD)),...
%     feature_list_truncated,para,1,5,10);

% (c) Edited by Cheng Lu,
% Biomedical Engineering,
% Case Western Reserve Univeristy, cleveland, OH. Aug, 2016
% If you have any problem feel free to contact me.
% Please address questions or comments to: hacylu@yahoo.com

% Terms of use: You are free to copy,
% distribute, display, and use this work, under the following
% conditions. (1) You must give the original authors credit. (2) You may
% not use or redistribute this work for commercial purposes. (3) You may
% not alter, transform, or build upon this work. (4) For any reuse or
% distribution, you must make clear to others the license terms of this
% work. (5) Any of these conditions can be waived if you get permission
% from the authors.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% v4 can return the balance acc
% 'nFold_AnyClassifier_withFeatureselection_v5_diffe' this version takes top features from different families specified in
% data_set, a cell contains feature values from different feature families
function [stats, feature_scores]= nFold_AnyClassifier_withFeatureselection_v5_diffe(data_set,data_labels,feature_list,para,shuffle,n,nIter,Subsets)


data_labels=double(data_labels);

if nargin < 8
    Subsets = {};
end
if nargin < 7
    nIter = 1;
end
if nargin < 6
    n = 4; % 3-fold cross-validation
end
if nargin < 5
    shuffle = 1; % randomized
end
data_set_cell=data_set;
data_set=data_set_cell{1};
data_set_all=[];
feature_list_all=[];
str_num_feat_config=[];
for i=1:length(data_set_cell)
    data_set_all=[data_set_all data_set_cell{i}];
    feature_list_all=[feature_list_all; feature_list{i}];
    str_num_feat_config=[str_num_feat_config,num2str([para.num_features_from_each_feat_families(i)]) ','];
end

str_num_feat_config=str_num_feat_config(1:end-1);

feature_list_cell=feature_list;
% if any(~xor(data_labels == 1, data_labels == -1)), error('Labels must be 1 and -1'); end

if size(data_set,1)~=length(data_labels)
    error('the size of the feature data should be the same as the label data!!!');
end

stats = struct; %cell(1,nIter);
for j=1:nIter
    fprintf('Iteration: %i\n',j);
    
    % reset total statistics
    Ttp = 0; Ttn = 0; Tfp = 0; Tfn = 0;
    
    if isempty(Subsets)

        if para.balanced_trainset
            [tra tes]=GenerateSubsets('nFold_balanced_trainset',data_set,data_labels,shuffle,n);
%             train=tra{1}; test=tes{1};
            %intersect(train,test)
        else
            [tra tes]=GenerateSubsets('nFold',data_set,data_labels,shuffle,n);
        end
        decision=zeros(size(data_labels)); prediction=zeros(size(data_labels));
    else
        tra{1} = Subsets{j}.training;
        tes{1} = Subsets{j}.testing;
        %         decision=zeros(size(tes{1})); prediction=zeros(size(tes{1}));
    end
    
    for i=1:n
        
        for i_feat_families=1:length(data_set_cell)
            fprintf(['Fold #' num2str(i) '\n']);
            data_set=data_set_cell{i_feat_families};
            feature_list=feature_list_cell{i_feat_families};
            training_set = data_set(tra{i},:);
            testing_set = data_set(tes{i},:);
            training_labels = data_labels(tra{i});%sum(training_labels)  sum(~training_labels)
            testing_labels = data_labels(tes{i});%sum(testing_labels) sum(~testing_labels)
            
            %%% do feature selection on the fly
            %% using mrmr
            if strcmp(para.featureranking,'mrmr')
                %         map the data in to binary values 0 1
                dataw_discrete=makeDataDiscrete_mrmr(training_set);
                %             dataw_discrete=training_set>t; check check check
                setAll=1:size(training_set,2);
                [idx_TTest_tmp{i_feat_families}] = mrmr_mid_d(dataw_discrete(:,setAll), training_labels, para.num_top_feature);
            end
            
            %% using random forest
            if strcmp(para.featureranking,'rf')
                options = statset('UseParallel','never','UseSubstreams','never');
                B = TreeBagger(50,training_set,training_labels,'FBoot',0.667, 'oobpred','on','OOBVarImp', 'on', 'Method','classification','NVarToSample','all','NPrint',4,'Options',options);
                variableimportance = B.OOBPermutedVarDeltaError;
                [t,idx]=sort(variableimportance,'descend');
                idx_TTest_tmp{i_feat_families}=idx(1:para.num_top_feature);
            end
            
            if strcmp(para.featureranking,'ttest') | strcmp(para.featureranking,'wilcoxon')
                %% using ttest
                if strcmp(para.featureranking,'ttest')
                    [TTidx,confidence] = prunefeatures_new(training_set, training_labels, 'ttestp');
                    %                 idx_TTest=TTidx(confidence<0.05);
                    %                 if isempty(idx_TTest)
                    idx_TTest=TTidx(1:min(para.num_top_feature*8,size(data_set,2)));
                    %                 end
                end
                
                if strcmp(para.featureranking,'wilcoxon')
                    [TTidx,confidence] = prunefeatures_new(training_set, training_labels, 'wilcoxon');
                    %                 idx_TTest=TTidx(confidence<0.5);
                    %                 if isempty(idx_TTest)
                    idx_TTest=TTidx(1:min(para.num_top_feature*8,size(data_set,2)));
                    %                 end
                end
                
                %%% lock down top features with low correlation
                set_candiF=Lpick_top_n_features_with_pvalue_correlation(training_set,idx_TTest,para.num_features_from_each_feat_families(i_feat_families),para.correlation_factor);
                set_fff{i_feat_families}=feature_list(set_candiF)'; % training_set(:,373)
                idx_TTest_tmp{i_feat_families}=set_candiF;
            end
        end
        %% combine the top features from different feature families
%         set_top_feats_names_in_diff_feat_families=[];
        idx_TTest=[];
        offset=0;%feature index offset
        for itmp=1:length(data_set_cell)
%             set_top_feats_names_in_diff_feat_families=[set_top_feats_names_in_diff_feat_families set_fff{itmp}];
            idx_TTest=[idx_TTest idx_TTest_tmp{itmp}+offset];
            offset=offset+size(data_set_cell{itmp},2);
        end
        
        %% test on the testing set
        feature_scores=zeros(offset,1);
        
%         training_set
%         testing_set
        
        training_set = data_set_all(tra{i},:);
        testing_set = data_set_all(tes{i},:);
        %         a=setTopF_TTest{1};b=setTopF_TTest{2};
        %         strcmp
        %         interr=intersect(a,b);
        if  strcmp(para.feature_score_method,'addone')
            % add one value on the piceked features
            feature_scores(idx_TTest)=feature_scores(idx_TTest)+1;
        end
        
        if  strcmp(para.feature_score_method,'weighted')
            feature_scores(idx_TTest)=feature_scores(idx_TTest)+ linspace( para.num_top_feature ,1, length(idx_TTest))';
        end
        
        
        fprintf('on the fold, %d features are picked from %d diffrent feature families(distributed as %s)\n', length(idx_TTest), length(data_set_cell),str_num_feat_config);
        try
            if strcmp(para.classifier,'BaggedC45')
                [temp_stats,methodstring] = Classify( 'BaggedC45', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:));
            end
            
            if strcmp(para.classifier,'QDA')|| strcmp(para.classifier,'qda')
                [temp_stats,methodstring] = Classify( 'QDA', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:));
            end
            
            if strcmp(para.classifier,'LDA') ||strcmp(para.classifier,'lda')
                [temp_stats,methodstring] = Classify( 'LDA', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:));
            end
            
            if strcmp(para.classifier,'SVM')||strcmp(para.classifier,'svm')
                if exist('para.params','var')
                    params.kernel=para.params.kernel;
                    params.c_range=para.params.c_range;
                    params.g_range=para.params.g_range;
                    params.cvfolds=para.params.cvfolds;
                    [temp_stats,methodstring] = Classify( 'SVM', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:),params);
                    
                else
                    [temp_stats,methodstring] = Classify( 'SVM', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:));
                end
                temp_stats.decision=temp_stats.predicted_labels;
                temp_stats.prediction=temp_stats.prob_estimates(:,1);
            end
        catch
            display('Error while using LDA or QDA, the training data is linear dependent, use Random Forest for this fold instead\n');
            [temp_stats,methodstring] = Classify( 'BaggedC45', training_set(:,idx_TTest) , testing_set(:,idx_TTest), training_labels(:), testing_labels(:));
        end
        Ttp = Ttp + temp_stats.tp;
        Ttn = Ttn + temp_stats.tn;
        Tfp = Tfp + temp_stats.fp;
        Tfn = Tfn + temp_stats.fn;
        if ~isempty(Subsets)
            stats=temp_stats;
            return;
        end
        decision(tes{i}) = temp_stats.decision;
        
        %       decision(tes{i}) = temp_stats.prediction >= temp_stats.threshold;
        prediction(tes{i}) = temp_stats.prediction;
    end
    decision(decision==0) = -1;
    
    % output statistics
    if numel(unique(data_labels))>1 %numel(unique(testing_labels))>1
        if n == 1
            [FPR,TPR,T,AUC,OPTROCPT,~,~] = perfcurve(data_labels(tes{i}),prediction(tes{i}),1);
        else
            [FPR,TPR,T,AUC,OPTROCPT,~,~] = perfcurve(data_labels,prediction,1);
        end
        stats(j).AUC = AUC;
        stats(j).TPR = TPR;
        stats(j).FPR = FPR;
    else
        stats(j).AUC = [];
        stats(j).TPR = [];
        stats(j).FPR = [];
    end
    
    stats(j).tp = Ttp;
    stats(j).tn = Ttn;
    stats(j).fp = Tfp;
    stats(j).fn = Tfn;
    stats(j).acc = (Ttp+Ttn)/(Ttp+Ttn+Tfp+Tfn);
    stats(j).ppv = Ttp/(Ttp+Tfp);
    stats(j).sens = Ttp/(Ttp+Tfn);
    stats(j).spec = Ttn/(Tfp+Ttn);
    stats(j).subsets.training = tra;
    stats(j).subsets.testing = tes;
    stats(j).labels = data_labels;
    stats(j).decision = decision;
    stats(j).prediction = prediction;
    Pre = ((Ttp+Tfp)*(Ttp+Tfn) + (Ttn+Tfn)*(Ttn+Tfp)) / (Ttp+Ttn+Tfp+Tfn)^2;
    stats(j).kappa = (stats(j).acc - Pre) / (1 - Pre);
    
    
    % get a blance sens and spec to report
    if para.get_balance_sens_spec
        spe=1-FPR;
        labels=stats(j).labels;
        balanceAcc=(spe+TPR)/2;
        [~,maxIdx]=max(balanceAcc);
        stats(j).sens=TPR(maxIdx);
        stats(j).spec=1-FPR(maxIdx);
        stats(j).tp=round(stats(j).sens*sum(labels));
        stats(j).tn=round(stats(j).spec*sum(~labels));
        stats(j).fp=sum(~labels)-stats(j).tn;
        stats(j).fn=sum(labels)-stats(j).tp;
        stats(j).acc=(stats(j).tp+stats(j).tn)/length(labels);
        %% modeified other metrics if neccesary !!
        
    end
end