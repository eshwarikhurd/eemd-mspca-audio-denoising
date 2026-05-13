function []= emd_denoising(a)
tic
% Example: Converting a cell array to a numeric array
if iscell(a)
    a_numeric = cell2mat(a);  % Convert cell array to matrix
else
    a_numeric = a;  % If it's already numeric, keep it as-is
end
% Flatten a numeric array to a single-dimensional vector
a_vector = a_numeric(:);  % Convert to a single-dimensional vector
if isempty(a_vector) || ~isnumeric(a_vector)
    error("Input data 'a' must be a non-empty numeric vector.")
end

imf= emd(a_vector);
  imf=imf';
  s=size(imf);
  h=zeros(1,s(2));
  b=a';
  for i=1:s(2)
    h(i)=estimate_hurst_expo(imf(:,i)');
   if(h<0.5)
    b=b-imf(:,i)';
  end
  end
  % Flatten 'b' if it's multi-dimensional
if ismatrix(b) && size(b, 1) > 1 && size(b, 2) > 1
    b_vector = b(:);  % Convert to single-dimensional vector
else
    b_vector = b;  % If it's already a single-dimensional vector
end
% Inspect 's' to ensure it's not just zeros or empty
disp(s)  % Display the content of 's'

% Ensure 's' is numeric and has expected values
if isempty(s) || all(s == 0)
    error("Data to plot seems empty or invalid. Check your input data and operations leading to 's'.")
end

% Now, plot using the correct data
subplot(2,1,2)
plot(b_vector)

  %evaluate_metrics(a,b)
end