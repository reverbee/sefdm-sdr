%%
% Fine Freq Synchronization
% Главное, чтобы наш алгоритм FFS выполнялся по одинаковым отсчётам!
% Моделируя CTS + SD, надо подобрать отрезок в который точно попадут одинаковые отсчёты +
% чем больше отрезок, тем больше усреднение ==> точнее CFS (это надо проверить моделируя этим скриптом)
%
% Выполняется после компенсации (после CFS)
% !!! Испльзование LTS вместо STS ничего не меняет, поэтому можно делать по STS до FTS

%%
% Параметры
path(path, './functions/');
path(path, '../02_ofdm_phy_802_11a_model/ofdm_phy_802_11a/');

N_subcarrier = 64;
N_ofdm_sym   = 2;
N_bit        = N_ofdm_sym * N_subcarrier;
Fd           = 10 * 10^6;

window_mode = 'no_window_overlap'; % 'window_overlap' or 'no_window_overlap' // параметр ПРЕАМБУЛЫ

N_iter      = 1e3; % кол-во итераций для накопления статистики
EbNo        = [2, 4, 8]; % дБ
time_offset = 200;
% Для -0.5 <= e <= 0.5 верхняя F в Гц будет 78125 Гц (Перевод из "e" в Гц: e*Fd/N_fft)
deltaF      = [0, 5 * 10^3, 15 * 10^3, 50 * 10^3]; % Гц, частотная отстройка УЖЕ ПОСЛЕ ПЕРВИЧНОЙ КОМПЕНСАЦИИ

% Алгоритм FFS
% Величина (L_ffs + D_ffs) определяет размер окна, по которой находим FFO
% !!! Диапазон оценки определяется D_s: | e == deltfaF / (1/Tofdm) | <= Nfft / (2 * D_s)
L_ffs = 64; % размер окна суммирования == усреднения в данном случае, определяет точность
D_ffs = 64; % длина одного STS == определяет возможный диапазон частотной отстройки
startAlgorithmSample = time_offset + 1; % отсчёт с которого стартует алгоритм FFS
roundToInteger = 'no'; % 'yes' or 'no' округлять до целого в сторону нуля или нет ?? МБ ВАЩЕ НАФИГ ???

%%
% Модель
tx_bit = randi([0 1], 1, N_bit);

% BPSK
tx_bpsk_sym = complex( zeros(1, N_bit) );
tx_bpsk_sym(tx_bit == 1) = -1 + 1i * 0;
tx_bpsk_sym(tx_bit == 0) = +1 + 1i * 0;

% OFDM
tx_ofdm_sym = reshape(tx_bpsk_sym, N_subcarrier, N_ofdm_sym);
tx_ofdm_sym = ifft(tx_ofdm_sym, N_subcarrier);
tx_ofdm_sym = reshape(tx_ofdm_sym, 1, N_bit);

Eb = sum( abs(tx_ofdm_sym) .^ 2 ) / N_bit;

% Add preamble
if strcmp(window_mode, 'window_overlap')

	STS = GenerateSTS('Tx');
	LTS = GenerateLTS('Tx');
	preamble = [ STS(1 : end  - 1), ... % STS
	             STS(end) + LTS(1), LTS(2 : end - 1), ... % LTS // с учётом перекрытия
	             LTS(end) ]; % кусок перекрытия для следующего OFDM-символа
	txSig = [ preamble(1 : end - 1), ... % преамбула
	          preamble(end) + 0.5 * tx_ofdm_sym(1), tx_ofdm_sym(2 : end)]; % полезная нагрузка с учётом перекрытия

else % strcmp(window_mode, 'no_window_overlap')

	STS = GenerateSTS('Rx');
	LTS = GenerateLTS('Rx');
	preamble    = [STS, LTS];
	txSig = [preamble, tx_ofdm_sym]; % полезная нагрузка с учётом перекрытия

end


% AWGN + time_offset + freq_offset
estFFO_3d = zeros(N_iter, length(deltaF), length(EbNo));
for k = 1 : N_iter

	for j = 1 : length(deltaF)

		for i = 1 : length(EbNo)

			No = Eb / ( 10^(EbNo(i) / 10) );
		% 	No = 0; % minus AWGN

			rxSig = [         sqrt(No / 2) * randn(1, time_offset)   + 1i * sqrt(No / 2) * randn(1, time_offset), ...
					  txSig + sqrt(No / 2) * randn(1, length(txSig)) + 1i * sqrt(No / 2) * randn(1, length(txSig)), ...
							  sqrt(No / 2) * randn(1, time_offset) +   1i * sqrt(No / 2) * randn(1, time_offset) ];
			rxSig = rxSig .* exp(1i * 2 * pi * deltaF(j) * (1 : length(rxSig)) / Fd);

			% Fine Freq Synch
			estFFO = FreqSynch( rxSig, L_ffs, D_ffs, startAlgorithmSample, roundToInteger);

			estFFO_3d(k, j, i) = estFFO;

		end

	end

end


%%
% Инфа
fprintf('\nИспользуются:\n');
fprintf('  N_fft          = %d\n', N_subcarrier);
fprintf('  F_d            = %d Гц\n', Fd);
fprintf('  L_cfs          = %d (размер окна суммирования - определяет точность)\n', L_ffs);
fprintf('  D_s            = %d (величина сдвига - определяет диапазон)\n\n', D_ffs);
fprintf('  deltaF_subcarr = %d Гц (расстояние между поднесущими)\n\n', Fd / N_subcarrier);
fprintf('Максимально возможная оценка частотной остройки при данных параметрах следующая:\n');
fprintf('e      = %.3f (относительная частотная отстройка)\n', N_subcarrier / (2 * D_ffs));
fprintf('deltaF = %.3f Гц (частотная отстройка)\n', Fd / (2 * D_ffs));

fprintf('Перевод из "e" в Гц: e*Fd/N_fft == e*%.2f\n\n', Fd / N_subcarrier);

% Переведём deltaF в "e"
deltaF = deltaF * N_subcarrier / Fd;
for j = 1 : length(deltaF)

	figure;

	for i = 1 : length(EbNo) 
		
		subplot(length(EbNo), 1, i);
		ar_1d = reshape(estFFO_3d(:, j, i), 1, []);
		
		ar_1d = ar_1d + deltaF(j);

		hist(ar_1d, min(ar_1d) : 0.001 : max(ar_1d));
		hold on;
		stem((-1)*deltaF(j), 5, 'Color', 'red');
		stem(deltaF(j), 5, 'Color', 'red');
		hold off;
		xlabel('e+e_{est}');
		title({ ['EbNo = ', num2str(EbNo(i)), ' dB'], ...
				['e = ', num2str(deltaF(j))] });
		grid on;

	end
end

fprintf('Оценка "e+e_est" - оставшееся после компенсации частотная отстройка!!!\n');

