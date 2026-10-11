function plot_decomposition(in_wav, out_png)
%PLOT_DECOMPOSITION Show what the EMD-based methods keep and remove.
%   plot_decomposition(in_wav, out_png) decomposes the (noisy) clip and saves
%   a figure with three views:
%     - EMD IMFs with their Hurst exponent (EMD-Hurst removes H < 0.5)
%     - singular values of each IMF's Hankel matrix (EMD-SVD, first pass)
%       against its 0.6*median threshold
%     - variance contribution rate of each EEMD component (EEMD-MSPCA drops
%       the leading components below 0.01)
[x, fs] = audioread(in_wav);
x = mean(x, 2);

blue = hex2rgb('#2a78d6'); gray = hex2rgb('#898781'); ink = hex2rgb('#0b0b0b');
orange = hex2rgb('#eb6834'); surface = hex2rgb('#fcfcfb');
ramp = hex2rgb(["#9ec5f4"; "#6da7ec"; "#3987e5"; "#256abf"; "#184f95"; "#0d366b"]);

imf = emd(x, 'Display', 0);
n = size(imf, 2);
H = arrayfun(@(i) estimate_hurst(imf(:, i)), 1:n);

fig = figure('Visible', 'off', 'Color', surface, 'Position', [0 0 1400 900]);
tl = tiledlayout(fig, n, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
[~, name] = fileparts(in_wav);
title(tl, sprintf('Decomposition of %s', strrep(name, '_', '\_')), 'Color', ink, 'FontWeight', 'bold');
t = (0:numel(x) - 1) / fs;
for i = 1:n
    ax = nexttile(tl, 2 * i - 1);
    removed = H(i) < 0.5;
    plot(ax, t, imf(:, i), 'Color', ifelse(removed, gray, blue), 'LineWidth', 0.5);
    style(ax, surface);
    ylabel(ax, sprintf('IMF %d', i), 'Color', ink);
    text(ax, 0.995, 0.85, sprintf('H = %.2f%s', H(i), ifelse(removed, ', removed', '')), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', 'Color', ink, 'FontSize', 8, ...
        'BackgroundColor', surface, 'Margin', 1);
    if i == 1
        title(ax, 'EMD IMFs and Hurst exponent (gray = removed by EMD-Hurst)', 'Color', ink);
    end
    if i < n, ax.XTickLabel = []; else, xlabel(ax, 'Time (s)'); end
end

% Right column, top half: EMD-SVD singular value spectra.
ax = nexttile(tl, 2, [floor(n / 2), 1]);
hold(ax, 'on');
L = 20;
for i = 1:min(6, n)
    s = svd(hankel_matrix(imf(:, i), L), 'econ');
    s = s / s(1);
    c = ramp(min(i, size(ramp, 1)), :);
    plot(ax, 1:L, s, '-o', 'Color', c, 'MarkerFaceColor', c, 'MarkerEdgeColor', c, ...
        'MarkerSize', 3, 'LineWidth', 1.5, 'DisplayName', sprintf('IMF %d', i));
    yline(ax, 0.6 * median(s), ':', 'Color', c, 'HandleVisibility', 'off');
end
set(ax, 'YScale', 'log');
style(ax, surface);
legend(ax, 'Location', 'southwest', 'Box', 'off', 'NumColumns', 3, 'TextColor', ink);
xlabel(ax, 'Singular value index'); ylabel(ax, 'Normalized singular value');
title(ax, 'EMD-SVD: singular values per IMF (dotted = 0.6 x median threshold)', 'Color', ink);

% Right column, bottom half: EEMD variance contribution rates.
ax = nexttile(tl, 2 * (floor(n / 2) + 1), [n - floor(n / 2), 1]);
c = eemd(x, seed=0);
v = var(c, 1, 1);
vcr = v / sum(v);
first = find(vcr >= 0.01, 1);
b = bar(ax, vcr, 0.6, 'FaceColor', 'flat', 'EdgeColor', 'none');
b.CData = repmat(orange, numel(vcr), 1);
b.CData(1:first - 1, :) = repmat(gray, first - 1, 1);
yline(ax, 0.01, '-', 'VCR = 0.01', 'Color', gray, 'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom');
set(ax, 'YScale', 'log');
style(ax, surface);
labels = [compose('c%d', 1:numel(vcr) - 1), {'res'}];
set(ax, 'XTick', 1:numel(vcr), 'XTickLabel', labels);
xlabel(ax, 'EEMD component'); ylabel(ax, 'Variance contribution rate');
title(ax, 'EEMD-MSPCA: components kept (orange) and dropped (gray)', 'Color', ink);

exportgraphics(fig, out_png, 'Resolution', 150, 'BackgroundColor', surface);
close(fig);
end

function style(ax, surface)
set(ax, 'Color', surface, 'Box', 'off', 'TickDir', 'out', 'XColor', hex2rgb('#52514e'), ...
    'YColor', hex2rgb('#52514e'), 'GridColor', hex2rgb('#e1e0d9'), 'GridAlpha', 1, 'FontSize', 8);
grid(ax, 'on');
set(ax, 'XMinorGrid', 'off', 'YMinorGrid', 'off');
end

function out = ifelse(cond, a, b)
if cond, out = a; else, out = b; end
end

function rgb = hex2rgb(hex)
hex = char(erase(string(hex), '#'));
rgb = reshape(sscanf(hex.', '%2x'), 3, []).' / 255;
end
