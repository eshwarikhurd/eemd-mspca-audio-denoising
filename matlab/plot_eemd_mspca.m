function plot_eemd_mspca(in_wav, out_png, clean_wav)
%PLOT_EEMD_MSPCA Show what each step of EEMD-MSPCA does to a (noisy) clip.
%   plot_eemd_mspca(in_wav, out_png) runs denoise_eemd_mspca with its default
%   settings and saves a figure in the spirit of Peng et al. (2021), Figs. 3-4:
%     - left: every EEMD component before (light) and after (orange)
%       denoising; components dropped by the VCR rule are gray
%     - cumulative eigenvalue share of each component's Hankel matrix, with
%       the 85% cut-off that decides how many principal components are kept
%     - energy of each component before denoising, after PCA and after the
%       soft threshold, showing which step removes what
%     - a short window of the output against the input
%   plot_eemd_mspca(in_wav, out_png, clean_wav) also draws the clean clip in
%   that window.
[x, fs] = audioread(in_wav);
x = mean(x, 2);
[y, info] = denoise_eemd_mspca(x);
clean = [];
if nargin > 2
    clean = mean(audioread(clean_wav), 2);
    clean = clean(1:numel(x));
end

ink = hex2rgb('#0b0b0b'); ink2 = hex2rgb('#52514e'); gray = hex2rgb('#898781');
light = hex2rgb('#9ec5f4'); blue = hex2rgb('#2a78d6'); orange = hex2rgb('#eb6834');
surface = hex2rgb('#fcfcfb');
ramp = hex2rgb(["#86b6ef"; "#3987e5"; "#256abf"; "#184f95"; "#0d366b"]);

c = info.components;
n = size(c, 2);
names = [compose('c%d', 1:n - 1), {'res'}];
kept = (1:n) >= info.first;
t = (0:numel(x) - 1) / fs;

fig = figure('Visible', 'off', 'Color', surface, 'Position', [0 0 1500 max(900, 85 * n)]);
tl = tiledlayout(fig, n, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
[~, name] = fileparts(in_wav);
title(tl, sprintf('EEMD-MSPCA on %s', strrep(name, '_', '\_')), 'Color', ink, 'FontWeight', 'bold');

% Left column: each component before and after.
for i = 1:n
    ax = nexttile(tl, 2 * i - 1);
    hold(ax, 'on');
    if kept(i)
        plot(ax, t, c(:, i), 'Color', light, 'LineWidth', 0.5);
        plot(ax, t, info.denoised(:, i), 'Color', orange, 'LineWidth', 0.5);
        note = sprintf('VCR %.3f · %d of %d PCs · T = %.2g', info.vcr(i), info.k(i), ...
            numel(info.lambda(:, i)), info.T(i));
    else
        plot(ax, t, c(:, i), 'Color', gray, 'LineWidth', 0.5);
        note = sprintf('VCR %.3f < %.2g · dropped', info.vcr(i), info.vcr_min);
    end
    style(ax, surface);
    ylabel(ax, names{i}, 'Color', ink);
    lim = max(abs(c(:, i))) * 1.1 + eps;
    ylim(ax, [-lim lim]);
    xlim(ax, [0 t(end)]);
    text(ax, 0.995, 0.15, note, 'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'Color', ink, 'FontSize', 8);
    if i == 1
        title(ax, 'EEMD components: before (light blue), after (orange), dropped (gray)', 'Color', ink);
    end
    if i < n, ax.XTickLabel = []; else, xlabel(ax, 'Time (s)'); end
end

rows = floor(n / 3);
% Right column, panel 1: cumulative eigenvalue share per kept component.
ax = nexttile(tl, 2, [rows, 1]);
hold(ax, 'on');
idx = find(kept);
cols = interp1(linspace(0, 1, size(ramp, 1)), ramp, linspace(0, 1, max(numel(idx), 2)));
for j = 1:numel(idx)
    i = idx(j);
    lam = info.lambda(:, i);
    share = cumsum(lam) / sum(lam);
    plot(ax, 1:numel(share), 100 * share, '-o', 'Color', cols(j, :), 'MarkerFaceColor', cols(j, :), ...
        'MarkerEdgeColor', cols(j, :), 'MarkerSize', 3, 'LineWidth', 1.5, 'DisplayName', names{i});
end
yline(ax, 100 * info.energy, '-', sprintf('%g%% cut-off', 100 * info.energy), 'Color', gray, ...
    'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
style(ax, surface);
ylim(ax, [0 101]);
xlabel(ax, 'Number of principal components'); ylabel(ax, 'Cumulative eigenvalue share (%)');
legend(ax, 'Location', 'southeast', 'Box', 'off', 'NumColumns', 2, 'TextColor', ink);
title(ax, 'Hankel PCA: components kept until the cut-off is reached', 'Color', ink);

% Panel 2: energy per component through the steps.
ax = nexttile(tl, 2 * (rows + 1), [rows, 1]);
E = [sum(c.^2, 1); sum(info.after_pca.^2, 1); sum(info.denoised.^2, 1)]' / sum(x.^2);
E(E == 0) = NaN;
b = bar(ax, E, 'grouped', 'EdgeColor', 'none', 'BarWidth', 0.9);
b(1).FaceColor = light; b(2).FaceColor = blue; b(3).FaceColor = orange;
set(ax, 'YScale', 'log', 'XTick', 1:n, 'XTickLabel', names);
style(ax, surface);
ylabel(ax, 'Energy / input energy');
legend(ax, {'EEMD component', 'after PCA', 'after soft threshold'}, 'Location', 'northeast', ...
    'Box', 'off', 'TextColor', ink);
title(ax, 'Where the energy goes (missing bar = removed entirely)', 'Color', ink);

% Panel 3: a short window of the result.
ax = nexttile(tl, 2 * (2 * rows + 1), [n - 2 * rows, 1]);
hold(ax, 'on');
[~, mid] = max(movmean(x.^2, round(0.04 * fs)));
w = max(1, mid - round(0.02 * fs)):min(numel(x), mid + round(0.02 * fs));
plot(ax, t(w) * 1000, x(w), 'Color', gray, 'LineWidth', 1, 'DisplayName', 'input');
if ~isempty(clean)
    plot(ax, t(w) * 1000, clean(w), 'Color', ink, 'LineWidth', 1.5, 'DisplayName', 'clean');
end
plot(ax, t(w) * 1000, y(w), 'Color', orange, 'LineWidth', 1.5, 'DisplayName', 'EEMD-MSPCA output');
style(ax, surface);
xlabel(ax, 'Time (ms)');
legend(ax, 'Location', 'southeast', 'Box', 'off', 'TextColor', ink);
if ~isempty(clean)
    title(ax, sprintf('Loudest 40 ms (SNR %.1f → %.1f dB)', snr_db(x, clean), snr_db(y, clean)), 'Color', ink);
else
    title(ax, 'Loudest 40 ms', 'Color', ink);
end
ax.YAxis.Color = ink2;

exportgraphics(fig, out_png, 'Resolution', 150, 'BackgroundColor', surface);
close(fig);
end

function style(ax, surface)
set(ax, 'Color', surface, 'Box', 'off', 'TickDir', 'out', 'XColor', hex2rgb('#52514e'), ...
    'YColor', hex2rgb('#52514e'), 'GridColor', hex2rgb('#e1e0d9'), 'GridAlpha', 1, 'FontSize', 8);
grid(ax, 'on');
set(ax, 'XMinorGrid', 'off', 'YMinorGrid', 'off');
end

function rgb = hex2rgb(hex)
hex = char(erase(string(hex), '#'));
rgb = reshape(sscanf(hex.', '%2x'), 3, []).' / 255;
end
