function H = estimate_hurst(x)
%ESTIMATE_HURST Hurst exponent by rescaled-range (R/S) analysis.
%   H ~ 0.5 for white noise, < 0.5 for anti-persistent and > 0.5 for
%   persistent signals.
x = x(:);
N = numel(x);
sizes = unique(floor(logspace(log10(8), log10(N / 2), 20)));
rs = nan(size(sizes));
for k = 1:numel(sizes)
    n = sizes(k);
    seg = reshape(x(1:floor(N / n) * n), n, []);
    z = cumsum(seg - mean(seg, 1), 1);
    R = max(z, [], 1) - min(z, [], 1);
    S = std(seg, 1, 1);
    ok = S > 0;
    if any(ok)
        rs(k) = mean(R(ok) ./ S(ok));
    end
end
ok = isfinite(rs) & rs > 0;
p = polyfit(log(sizes(ok)), log(rs(ok)), 1);
H = p(1);
end
