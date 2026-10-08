function denoise_batch(work_dir)
%DENOISE_BATCH Run every job file jobs_<method>.txt in work_dir.
%   Each line of a job file is "<input wav>\t<output wav>" (paths relative to
%   work_dir). Outputs are written as 32-bit float WAV, and the runtime of
%   each file is written to times_<method>.csv. Used by python/run_benchmark.py.
%
%   A job name can carry options for the method after an '@', e.g.
%   jobs_emd_svd@smooth=1,thr=0.3.txt runs denoise(x, 'emd_svd', smooth=1,
%   thr=0.3). Used by python/run_sweep.py.
jobs = dir(fullfile(work_dir, 'jobs_*.txt'));
for j = 1:numel(jobs)
    variant = extractBetween(jobs(j).name, 'jobs_', '.txt');
    variant = variant{1};
    [method, options] = parse_variant(variant);
    lines = readlines(fullfile(work_dir, jobs(j).name), 'EmptyLineRule', 'skip');
    fprintf('%s: %d files\n', variant, numel(lines));
    times = zeros(numel(lines), 1);
    for k = 1:numel(lines)
        parts = split(lines(k), sprintf('\t'));
        [x, fs] = audioread(fullfile(work_dir, parts(1)));
        x = mean(x, 2);
        t = tic;
        y = denoise(x, method, options{:});
        times(k) = toc(t);
        out = fullfile(work_dir, parts(2));
        if ~isfolder(fileparts(out)), mkdir(fileparts(out)); end
        audiowrite(out, single(y), fs, 'BitsPerSample', 32);
    end
    writetable(table(lines, times, 'VariableNames', {'job', 'seconds'}), ...
        fullfile(work_dir, "times_" + variant + ".csv"));
end
end

function [method, options] = parse_variant(variant)
% 'emd_svd@smooth=1,thr=0.3' -> 'emd_svd', {'smooth', 1, 'thr', 0.3}
parts = split(string(variant), '@');
method = char(parts(1));
options = {};
if numel(parts) > 1
    for kv = split(parts(2), ',')'
        pair = split(kv, '=');
        value = str2double(pair(2));
        if isnan(value)
            value = char(pair(2));
        end
        options(end + 1:end + 2) = {char(pair(1)), value}; %#ok<AGROW>
    end
end
end
