function x = diagonal_averaging(H)
%DIAGONAL_AVERAGING Inverse of HANKEL_MATRIX: average each anti-diagonal.
%   Returns a column vector of length L+K-1.
[L, K] = size(H);
idx = (1:L)' + (0:K-1);
x = accumarray(idx(:), H(:)) ./ accumarray(idx(:), 1);
end
