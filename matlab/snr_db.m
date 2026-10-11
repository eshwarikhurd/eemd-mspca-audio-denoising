function s = snr_db(y, ref)
%SNR_DB SNR (dB) of y against the clean reference ref.
n = min(numel(y), numel(ref));
y = y(1:n); ref = ref(1:n);
s = 10 * log10(sum(ref(:).^2) / sum((ref(:) - y(:)).^2));
end
