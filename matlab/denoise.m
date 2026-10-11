function y = denoise(x, method, varargin)
%DENOISE Run a denoising method by name: 'emd_svd', 'wavelet', 'emd_hurst'
%   or 'eemd_mspca'.
%   Extra arguments are passed on as name-value options.
switch method
    case 'emd_svd'
        y = denoise_emd_svd(x, varargin{:});
    case 'wavelet'
        y = denoise_wavelet(x, varargin{:});
    case 'emd_hurst'
        y = denoise_emd_hurst(x, varargin{:});
    case 'eemd_mspca'
        y = denoise_eemd_mspca(x, varargin{:});
    otherwise
        error('denoise:unknownMethod', 'Unknown method "%s".', method);
end
end
