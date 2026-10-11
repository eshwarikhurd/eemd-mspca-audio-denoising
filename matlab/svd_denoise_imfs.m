function y = svd_denoise_imfs(imf, L, thr)
%SVD_DENOISE_IMFS Hankel-SVD denoise each IMF (columns of imf) and sum them.
%   Singular values below thr*median(sigma) are set to zero.
[N, n_imfs] = size(imf);
y = zeros(N, 1);
for i = 1:n_imfs
    H = hankel_matrix(imf(:, i), L);
    [U, S, V] = svd(H, 'econ');
    s = diag(S);
    s(s < thr * median(s)) = 0;
    y = y + diagonal_averaging(U * diag(s) * V');
end
end
