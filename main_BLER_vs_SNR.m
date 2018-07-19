function main_BLER_vs_SNR(BG, Z_c, iterations, target_block_errors, target_BLER, EsN0_start, EsN0_delta, seed)
% MAIN_BLER_VS_SNR Plots Block Error Rate (BLER) versus Signal to Noise
% Ratio (SNR) for 3GPP New Radio LDPC code.
%   target_block_errors should be an integer scalar. The simulation of each
%   SNR for each coding rate will continue until this number of block
%   errors have been observed. A value of 100 is sufficient to obtain
%   smooth BLER plots for most values of A. Higher values will give
%   smoother plots, at the cost of requiring longer simulations.
%
%   target_BLER should be a real scalar, in the range (0, 1). The
%   simulation of each coding rate will continue until the BLER plot
%   reaches this value.
%
%   EsN0_start should be a real row vector, having the same length as the
%   vector of coding rates. Each value specifies the Es/N0 SNR to begin at
%   for the simulation of the corresponding coding rate.
%
%   EsN0_delta should be a real scalar, having a value greater than 0.
%   The Es/N0 SNR is incremented by this amount whenever
%   target_block_errors number of block errors has been observed for the
%   previous SNR. This continues until the BLER reaches target_BLER.
%
%   seed should be an integer scalar. This value is used to seed the random
%   number generator, allowing identical results to be reproduced by using
%   the same seed. When running parallel instances of this simulation,
%   different seeds should be used for each instance, in order to collect
%   different results that can be aggregated together.

% Default values
if nargin == 0
    BG = 1;
    Z_c = 2;
    iterations = 50;
    target_block_errors = 10;
    target_BLER = 1e-3;
    EsN0_start = -10;
    EsN0_delta = 0.5;
    seed = 0;
end

% Seed the random number generator
rng(seed);

    hMod = comm.PSKModulator(4, 'BitInput',true);


% Consider each base graph in turn
for BG_index = 1:length(BG)
    
    % Create a figure to plot the results.
    figure
    axes1 = axes('YScale','log');
    title(['3GPP New Radio LDPC code, BG = ',num2str(BG(BG_index)),', iterations = ',num2str(iterations),', errors = ',num2str(target_block_errors),', QPSK, AWGN']);
    ylabel('BLER');
    xlabel('E_s/N_0 [dB]');
    ylim([target_BLER,1]);
    hold on
    drawnow
    
    % Consider each lifting size in turn
    for Z_index = 1:length(Z_c)
        
        % Create the plot
        plot1 = plot(nan,'Parent',axes1);
        legend(cellstr(num2str(Z_c(1:Z_index)', 'Z_c=%d')),'Location','southwest');
        
        % Counters to store the number of bits and errors simulated so far
        block_counts=[];
        block_error_counts=[];
        EsN0s = [];
        
        % Open a file to save the results into.
        filename = ['results/BLER_vs_SNR_',num2str(BG(BG_index)),'_',num2str(Z_c(Z_index)),'_',num2str(iterations),'_',num2str(target_block_errors),'_',num2str(seed)];
        fid = fopen([filename,'.txt'],'w');
        if fid == -1
            error('Could not open %s.txt',filename);
        end
        
        % Initialise the BLER and SNR
        BLER = 1;
        EsN0 = EsN0_start;
        
        found_start = false;
        
        % Skip any encoded block lengths that generate errors
        try

            hEnc = NRLDPCEncoder('BG',BG(BG_index),'Z_c',Z_c(Z_index));            
            hDec = NRLDPCDecoder('BG',BG(BG_index),'Z_c',Z_c(Z_index),'iterations',iterations);
            K = hEnc.K;
            K_prime = K;
            hEnc.K_prime = K_prime;
            hDec.K_prime = K_prime;
            
            
            % Loop over the SNRs
            while BLER > target_BLER
                hChan = comm.AWGNChannel('NoiseMethod','Signal to noise ratio (SNR)','SNR',EsN0);
                hDemod = comm.PSKDemodulator(4, 'BitOutput',true, 'DecisionMethod','Log-likelihood ratio', 'Variance', 1/10^(hChan.SNR/10));
                
                
                % Start new counters
                block_counts(end+1) = 0;
                block_error_counts(end+1) = 0;
                EsN0s(end+1) = EsN0;
                
                keep_going = true;
                
                % Continue the simulation until enough block errors have been simulated
                while keep_going && block_error_counts(end) < target_block_errors
                    
                    b = round(rand(K_prime,1));                    
                    c = [b;NaN(K-K_prime,1)];
                    d = step(hEnc,c); 
                    e = d(~isnan(d));
                    
                    tx = step(hMod, e);
                    rx = step(hChan, tx);
                    e_tilde = step(hDemod, rx);
                    d_tilde = d;
                    d_tilde(~isnan(d)) = e_tilde;
                    c_hat = step(hDec, d_tilde);
                    b_hat = c_hat(~isnan(c_hat));
                    
                    if found_start == false && ~isequal(b,b_hat)
                        keep_going = false;
                        BLER = 1;
                    else
                        found_start = true;
                        
                        % Determine if we have a block error
                        if ~isequal(b,b_hat)
                            block_error_counts(end) = block_error_counts(end) + 1;
                        end
                        
                        % Accumulate the number of blocks that have been simulated
                        % so far
                        block_counts(end) = block_counts(end) + 1;
                        
                        % Calculate the BLER and save it in the file
                        BLER = block_error_counts(end)/block_counts(end);
                        
                        % Plot the BLER vs SNR results
                        set(plot1,'XData',EsN0s);
                        set(plot1,'YData',block_error_counts./block_counts);
                        drawnow
                    end
                end
                
                if BLER < 1
                    fprintf(fid,'%f\t%e\n',EsN0,BLER);
                end
                
                % Update the SNR, ready for the next loop
                EsN0 = EsN0 + EsN0_delta;
                
            end
        catch ME
            if strcmp(ME.identifier, 'ldpc_3gpp_matlab:UnsupportedBlockLength')
                warning('ldpc_3gpp_matlab:UnsupportedBlockLength','The combination of base graph BG=%d and lifting size Z=%d is not supported. %s',BG(BG_index),Z_c(Z_index), getReport(ME, 'basic', 'hyperlinks', 'on' ));
                continue
            else
                rethrow(ME);
            end
        end
        
        % Close the file
        fclose(fid);
    end
end




