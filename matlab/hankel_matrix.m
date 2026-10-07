function H = hankel_matrix(x, L)
%HANKEL_MATRIX L-by-(N-L+1) trajectory matrix with H(i,j) = x(i+j-1).
x = x(:);
H = hankel(x(1:L), x(L:end));
end
