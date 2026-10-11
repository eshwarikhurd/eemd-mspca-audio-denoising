function denoise_batch(work_dir)
%DENOISE_BATCH Run every job file jobs_<method>.txt in work_dir.
%   Each line of a job file is "<input wav>\t<output wav>" (paths relative to
%   work_dir). Outputs are written as 32-bit float WAV, and the runtime of
%   each file is written to times_<method>.csv. Used by python/run_benchmark.py.
jobs = dir(fullfile(work_dir, 'jobs_*.txt'));
for j = 1:numel(jobs)
    method = erase(erase(jobs(j).name, 'jobs_'), '.txt');
    lines = readlines(fullfile(work_dir, jobs(j).name), 'EmptyLineRule', 'skip');
    fprintf('%s: %d files\n', method, numel(lines));
    times = zeros(numel(lines), 1);
    for k = 1:numel(lines)
        parts = split(lines(k), sprintf('\t'));
        [x, fs] = audioread(fullfile(work_dir, parts(1)));
        x = mean(x, 2);
        t = tic;
        y = denoise(x, method);
        times(k) = toc(t);
        out = fullfile(work_dir, parts(2));
        if ~isfolder(fileparts(out)), mkdir(fileparts(out)); end
        audiowrite(out, single(y), fs, 'BitsPerSample', 32);
    end
    writetable(table(lines, times, 'VariableNames', {'job', 'seconds'}), ...
        fullfile(work_dir, "times_" + method + ".csv"));
end
end
