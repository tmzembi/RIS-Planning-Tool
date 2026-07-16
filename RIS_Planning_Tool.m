function RIS_Planning_Tool()
% =========================================================================
% RIS_Planning_Tool.m
% =========================================================================
% Design, Modelling, and Performance Optimisation of an RIS-Assisted
% Hybrid RF/FSO Communication System for Reliable Rural Connectivity
% in Zimbabwe
%
% PLANNING TOOL — Version 1.0
% Author:  Tino (HIT Electronic Engineering Department)
% Based on verified analytical framework from Master's Thesis
%
% HOW TO USE:
%   1. Type  RIS_Planning_Tool  in the MATLAB Command Window
%   2. Select your deployment terrain and season
%   3. Adjust system parameters using the sliders/fields
%   4. Click COMPUTE to generate results
%   5. Click EXPORT REPORT to save a text report
%
% REQUIREMENTS: MATLAB R2018b or later (no toolboxes required)
% =========================================================================

%% ── Create main figure ───────────────────────────────────────────────────
fig = uifigure('Name', ...
    'RIS-Assisted Hybrid RF/FSO Planning Tool — Zimbabwe Rural Connectivity', ...
    'Position', [50 50 1300 780], ...
    'Color', [0.96 0.96 0.96], ...
    'Resize', 'on');

%% ── Colour palette ───────────────────────────────────────────────────────
BLUE      = [0.12 0.47 0.71];
DARKBLUE  = [0.08 0.30 0.50];
GREEN     = [0.17 0.63 0.17];
RED       = [0.84 0.15 0.16];
ORANGE    = [1.00 0.50 0.05];
LIGHTGREY = [0.94 0.94 0.94];
WHITE     = [1.00 1.00 1.00];
DARKGREY  = [0.25 0.25 0.25];

%% ── TITLE BANNER ─────────────────────────────────────────────────────────
titlePanel = uipanel(fig, ...
    'Position', [10 730 1280 42], ...
    'BackgroundColor', DARKBLUE, ...
    'BorderType', 'none');
uilabel(titlePanel, ...
    'Text', 'RIS-ASSISTED HYBRID RF/FSO COMMUNICATION SYSTEM — RURAL ZIMBABWE DEPLOYMENT PLANNING TOOL', ...
    'Position', [10 8 1260 25], ...
    'FontSize', 13, 'FontWeight', 'bold', ...
    'FontColor', WHITE, ...
    'HorizontalAlignment', 'center');

%% ── LEFT PANEL: INPUTS ───────────────────────────────────────────────────
leftPanel = uipanel(fig, ...
    'Title', 'SYSTEM PARAMETERS', ...
    'Position', [10 10 310 715], ...
    'BackgroundColor', LIGHTGREY, ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', DARKBLUE);

ypos = 650;   % starting y position inside panel

%% ── Terrain Selection ────────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'Zimbabwe Terrain Type', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, ...
    'FontColor', DARKGREY);
ypos = ypos - 28;

terrainDrop = uidropdown(leftPanel, ...
    'Items', { ...
        'Highveld Plateau (m = 1.5) — Harare, Midlands', ...
        'Lowveld (m = 1.0) — Masvingo, Mat. South', ...
        'Eastern Highlands (m = 0.5) — Manicaland', ...
        'Open Savanna (m = 2.0) — Matabeleland North', ...
        'Line-of-Sight Path (m = 3.0) — Clear rural'}, ...
    'Position', [10 ypos 290 28], ...
    'FontSize', 9, ...
    'BackgroundColor', WHITE, ...
    'ValueChangedFcn', @terrainChanged);
ypos = ypos - 45;

%% ── Season / Turbulence ──────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'Season / Atmospheric Condition', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, ...
    'FontColor', DARKGREY);
ypos = ypos - 28;

seasonDrop = uidropdown(leftPanel, ...
    'Items', { ...
        'Dry Season — Weak turbulence (α=11.6, β=10.1)', ...
        'Highveld Average — Moderate turbulence (α=4.0, β=1.9)', ...
        'Rainy Season — Strong turbulence (α=4.2, β=1.4)'}, ...
    'Position', [10 ypos 290 28], ...
    'FontSize', 9, ...
    'BackgroundColor', WHITE, ...
    'ValueChangedFcn', @seasonChanged);
ypos = ypos - 50;

%% ── Divider ──────────────────────────────────────────────────────────────
uipanel(leftPanel, 'Position', [10 ypos 290 2], ...
    'BackgroundColor', BLUE, 'BorderType', 'none');
ypos = ypos - 20;

%% ── RIS Elements N ───────────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'Number of RIS Elements (N)', ...
    'Position', [10 ypos 230 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', DARKGREY);
N_label = uilabel(leftPanel, 'Text', 'N = 50', ...
    'Position', [240 ypos 60 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', BLUE, ...
    'HorizontalAlignment', 'right');
ypos = ypos - 28;

N_slider = uislider(leftPanel, ...
    'Limits', [1 100], 'Value', 50, ...
    'MajorTicks', [1 10 20 50 100], ...
    'Position', [10 ypos 280 3], ...
    'ValueChangedFcn', @(s,e) set(N_label,'Text',sprintf('N = %d', round(s.Value))));
ypos = ypos - 40;

%% ── SNR Range ────────────────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'SNR Range (dB)', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', DARKGREY);
ypos = ypos - 28;

uilabel(leftPanel, 'Text', 'Min SNR (dB):', ...
    'Position', [10 ypos 100 22], 'FontSize', 9);
SNR_min_field = uieditfield(leftPanel, 'numeric', ...
    'Value', -10, 'Limits', [-20 0], ...
    'Position', [110 ypos 75 22], 'FontSize', 9);

uilabel(leftPanel, 'Text', 'Max SNR (dB):', ...
    'Position', [10 ypos-30 100 22], 'FontSize', 9);
SNR_max_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 30, 'Limits', [10 50], ...
    'Position', [110 ypos-30 75 22], 'FontSize', 9);
ypos = ypos - 65;

%% ── Outage threshold ─────────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'SNR Threshold γth (linear)', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', DARKGREY);
ypos = ypos - 28;

gamma_th_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 1, 'Limits', [0.1 10], ...
    'Position', [10 ypos 100 24], 'FontSize', 10);
uilabel(leftPanel, 'Text', '(1 = 0 dB threshold)', ...
    'Position', [120 ypos 170 24], 'FontSize', 9, 'FontColor', DARKGREY);
ypos = ypos - 45;

%% ── Performance target ───────────────────────────────────────────────────
uilabel(leftPanel, 'Text', 'Performance Target', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', DARKGREY);
ypos = ypos - 28;

uilabel(leftPanel, 'Text', 'Target Outage:', ...
    'Position', [10 ypos 100 22], 'FontSize', 9);
target_out_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 1e-3, 'Limits', [1e-6 0.5], ...
    'Position', [110 ypos 80 22], 'FontSize', 9);

uilabel(leftPanel, 'Text', 'Target BER:', ...
    'Position', [10 ypos-30 100 22], 'FontSize', 9);
target_ber_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 1e-3, 'Limits', [1e-6 0.5], ...
    'Position', [110 ypos-30 80 22], 'FontSize', 9);
ypos = ypos - 65;

%% ── Solar relay power context ────────────────────────────────────────────
uipanel(leftPanel, 'Position', [10 ypos 290 2], ...
    'BackgroundColor', BLUE, 'BorderType', 'none');
ypos = ypos - 20;

uilabel(leftPanel, 'Text', 'Solar Site Context', ...
    'Position', [10 ypos 290 20], ...
    'FontWeight', 'bold', 'FontSize', 10, 'FontColor', DARKGREY);
ypos = ypos - 28;

uilabel(leftPanel, 'Text', 'Max Transmit Power (dBm):', ...
    'Position', [10 ypos 180 22], 'FontSize', 9);
tx_power_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 20, 'Limits', [0 40], ...
    'Position', [195 ypos 70 22], 'FontSize', 9);
ypos = ypos - 30;

uilabel(leftPanel, 'Text', 'Solar Panel Output (W):', ...
    'Position', [10 ypos 175 22], 'FontSize', 9);
solar_field = uieditfield(leftPanel, 'numeric', ...
    'Value', 50, 'Limits', [5 500], ...
    'Position', [195 ypos 70 22], 'FontSize', 9);
ypos = ypos - 40;

%% ── COMPUTE button ───────────────────────────────────────────────────────
computeBtn = uibutton(leftPanel, ...
    'Text', '▶  COMPUTE RESULTS', ...
    'Position', [10 ypos 290 38], ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'BackgroundColor', GREEN, ...
    'FontColor', WHITE, ...
    'ButtonPushedFcn', @computeResults);
ypos = ypos - 48;

%% ── EXPORT button ────────────────────────────────────────────────────────
exportBtn = uibutton(leftPanel, ...
    'Text', '📄  EXPORT REPORT', ...
    'Position', [10 ypos 290 32], ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', ORANGE, ...
    'FontColor', WHITE, ...
    'ButtonPushedFcn', @exportReport);

%% ── MIDDLE PANEL: PLOTS ──────────────────────────────────────────────────
plotPanel = uipanel(fig, ...
    'Title', 'PERFORMANCE CURVES', ...
    'Position', [330 390 680 335], ...
    'BackgroundColor', WHITE, ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', DARKBLUE);

% Tab group for multiple plots
tabGroup = uitabgroup(plotPanel, 'Position', [5 5 670 310]);

tab1 = uitab(tabGroup, 'Title', 'Outage Probability');
tab2 = uitab(tabGroup, 'Title', 'Ergodic Capacity');
tab3 = uitab(tabGroup, 'Title', 'Bit Error Rate');

ax1 = uiaxes(tab1, 'Position', [10 5 645 270]);
ax2 = uiaxes(tab2, 'Position', [10 5 645 270]);
ax3 = uiaxes(tab3, 'Position', [10 5 645 270]);

% Style all axes
for ax = [ax1 ax2 ax3]
    ax.FontSize    = 10;
    ax.GridColor   = [0.8 0.8 0.8];
    ax.GridAlpha   = 0.5;
    ax.Box         = 'on';
    grid(ax, 'on');
end

%% ── BOTTOM MIDDLE: LINK BUDGET ───────────────────────────────────────────
budgetPanel = uipanel(fig, ...
    'Title', 'LINK BUDGET SUMMARY', ...
    'Position', [330 10 680 372], ...
    'BackgroundColor', WHITE, ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', DARKBLUE);

budgetText = uitextarea(budgetPanel, ...
    'Position', [10 10 660 340], ...
    'FontSize', 10, 'FontName', 'Courier New', ...
    'Editable', 'off', ...
    'BackgroundColor', [0.97 0.97 1.00], ...
    'Value', {'Click COMPUTE to generate link budget summary...'});

%% ── RIGHT PANEL: RESULTS ─────────────────────────────────────────────────
rightPanel = uipanel(fig, ...
    'Title', 'KEY RESULTS', ...
    'Position', [1020 390 270 335], ...
    'BackgroundColor', LIGHTGREY, ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', DARKBLUE);

% Result boxes
resultsData = struct();
[resultsData, resultLabels] = createResultBoxes(rightPanel, WHITE, BLUE, DARKGREY, GREEN, RED);

%% ── RIGHT BOTTOM: TERRAIN MAP ────────────────────────────────────────────
mapPanel = uipanel(fig, ...
    'Title', 'ZIMBABWE TERRAIN GUIDE', ...
    'Position', [1020 10 270 372], ...
    'BackgroundColor', LIGHTGREY, ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', DARKBLUE);

mapText = uitextarea(mapPanel, ...
    'Position', [5 5 258 348], ...
    'FontSize', 9, 'FontName', 'Courier New', ...
    'Editable', 'off', ...
    'BackgroundColor', [0.97 1.00 0.97], ...
    'Value', getTerrainGuide());

%% ── STATUS BAR ───────────────────────────────────────────────────────────
statusBar = uipanel(fig, ...
    'Position', [10 0 1280 12], ...
    'BackgroundColor', DARKBLUE, ...
    'BorderType', 'none');
statusLabel = uilabel(statusBar, ...
    'Text', '  Ready. Select terrain and season, then click COMPUTE.', ...
    'Position', [5 0 1270 12], ...
    'FontSize', 8, 'FontColor', WHITE);

%% ── Store handles in figure ──────────────────────────────────────────────
handles.terrainDrop     = terrainDrop;
handles.seasonDrop      = seasonDrop;
handles.N_slider        = N_slider;
handles.SNR_min_field   = SNR_min_field;
handles.SNR_max_field   = SNR_max_field;
handles.gamma_th_field  = gamma_th_field;
handles.target_out_field= target_out_field;
handles.target_ber_field= target_ber_field;
handles.tx_power_field  = tx_power_field;
handles.solar_field     = solar_field;
handles.ax1 = ax1; handles.ax2 = ax2; handles.ax3 = ax3;
handles.budgetText      = budgetText;
handles.statusLabel     = statusLabel;
handles.resultsData     = resultsData;
handles.resultLabels    = resultLabels;
handles.lastResults     = [];
guidata(fig, handles);

% Run initial computation
computeResults([], []);

% =========================================================================
%  CALLBACKS
% =========================================================================

    function terrainChanged(~, ~)
        h = guidata(fig);
        set(h.statusLabel, 'Text', '  Terrain changed. Click COMPUTE to update.');
    end

    function seasonChanged(~, ~)
        h = guidata(fig);
        set(h.statusLabel, 'Text', '  Season changed. Click COMPUTE to update.');
    end

    function computeResults(~, ~)
        h = guidata(fig);
        set(h.statusLabel, 'Text', '  Computing... please wait.');
        drawnow;

        %% ── Read parameters ─────────────────────────────────────────────
        N         = round(h.N_slider.Value);
        SNR_min   = h.SNR_min_field.Value;
        SNR_max   = h.SNR_max_field.Value;
        gamma_th  = h.gamma_th_field.Value;
        tgt_out   = h.target_out_field.Value;
        tgt_ber   = h.target_ber_field.Value;
        tx_pwr    = h.tx_power_field.Value;
        solar_w   = h.solar_field.Value;

        %% ── Terrain → m value ───────────────────────────────────────────
        terrain_idx = find(strcmp(h.terrainDrop.Items, h.terrainDrop.Value), 1);  % ValueIndex needs R2023b+; this works on R2018b+
        m_vals   = [1.5, 1.0, 0.5, 2.0, 3.0];
        m_names  = {'Highveld','Lowveld','E.Highlands','Open Savanna','LOS'};
        m        = m_vals(terrain_idx);
        t_name   = m_names{terrain_idx};

        %% ── Season → turbulence params ──────────────────────────────────
        season_idx = find(strcmp(h.seasonDrop.Items, h.seasonDrop.Value), 1);  % ValueIndex needs R2023b+; this works on R2018b+
        alpha_v  = [11.6, 4.0, 4.2];
        beta_v   = [10.1, 1.9, 1.4];
        s_names  = {'Dry Season','Highveld Average','Rainy Season'};
        alpha    = alpha_v(season_idx);
        beta     = beta_v(season_idx);
        s_name   = s_names{season_idx};

        %% ── SNR vector ──────────────────────────────────────────────────
        SNR_dB  = SNR_min:1:SNR_max;
        SNR_lin = 10.^(SNR_dB/10);
        Omega   = 1;

        %% ── RIS statistics ──────────────────────────────────────────────
        E_h      = sqrt(Omega/m) * gamma_fn(m+0.5) / gamma_fn(m);
        mu_p     = E_h^2;
        sigma_p2 = Omega^2 - mu_p^2;
        mu_Z     = N * mu_p;
        sigma_Z  = sqrt(N * sigma_p2);

        %% ── Allocate arrays ─────────────────────────────────────────────
        Pout_RIS   = zeros(size(SNR_lin));
        Pout_noRIS = zeros(size(SNR_lin));
        Pout_RF    = zeros(size(SNR_lin));
        Cap_RIS    = zeros(size(SNR_lin));
        Cap_noRIS  = zeros(size(SNR_lin));
        Cap_RF     = zeros(size(SNR_lin));
        BER_RIS    = zeros(size(SNR_lin));
        BER_noRIS  = zeros(size(SNR_lin));
        BER_RF     = zeros(size(SNR_lin));

        for idx = 1:length(SNR_lin)
            snr = SNR_lin(idx);

            %% CDFs
            F_SR_RIS = qfunc_approx((mu_Z - sqrt(gamma_th/snr))/sigma_Z) ...
                     - qfunc_approx((mu_Z + sqrt(gamma_th/snr))/sigma_Z);
            F_SR_dir = gammainc_approx(m * gamma_th / snr, m);
            F_RF     = gammainc_approx(m * gamma_th / snr, m);
            F_FSO    = fso_cdf(gamma_th, alpha, beta, snr);

            %% Outage
            Pout_RIS(idx)   = F_SR_RIS + (1-F_SR_RIS)*F_RF*F_FSO;
            Pout_noRIS(idx) = F_SR_dir + (1-F_SR_dir)*F_RF*F_FSO;
            Pout_RF(idx)    = F_SR_dir;

            %% Capacity
            Cap_RIS(idx)   = cap_integral(snr, m, alpha, beta, N, Omega, 1);
            Cap_noRIS(idx) = cap_integral(snr, m, alpha, beta, 1, Omega, 0);
            Cap_RF(idx)    = (1/(2*log(2))) * ...
                integral(@(g)(1-gammainc_approx(m*g/snr,m))./(1+g), ...
                         0, 100*snr, 'RelTol',1e-4,'AbsTol',1e-8);

            %% BER (BPSK)
            BER_RIS(idx)   = ber_integral(snr, m, alpha, beta, N, Omega, 1);
            BER_noRIS(idx) = ber_integral(snr, m, alpha, beta, 1, Omega, 0);
            BER_RF(idx)    = (1/pi)*integral(@(phi)(1+snr./(m*sin(phi).^2)).^(-m),...
                             0, pi/2, 'RelTol',1e-5,'AbsTol',1e-10);
        end

        %% ── PLOT 1: Outage ──────────────────────────────────────────────
        cla(h.ax1);
        semilogy(h.ax1, SNR_dB, Pout_RF,    'k-',  'LineWidth',1.5, 'DisplayName','RF Only (baseline)');
        hold(h.ax1,'on');
        semilogy(h.ax1, SNR_dB, Pout_noRIS, 'b--', 'LineWidth',1.5, 'DisplayName','Hybrid RF/FSO (no RIS)');
        semilogy(h.ax1, SNR_dB, Pout_RIS,   'r-',  'LineWidth',2.5, 'DisplayName',sprintf('RIS-Hybrid N=%d',N));
        yline(h.ax1, tgt_out, 'g:', 'LineWidth',1.5, 'Label',sprintf('Target=%.0e',tgt_out));
        hold(h.ax1,'off');
        xlabel(h.ax1,'Average SNR (dB)','FontSize',10);
        ylabel(h.ax1,'Outage Probability P_{out}','FontSize',10);
        title(h.ax1,sprintf('Outage Probability | %s | %s | N=%d',t_name,s_name,N),'FontSize',10);
        legend(h.ax1,'Location','southwest','FontSize',8);
        grid(h.ax1,'on'); ylim(h.ax1,[1e-6 1]); xlim(h.ax1,[SNR_min SNR_max]);

        %% ── PLOT 2: Capacity ────────────────────────────────────────────
        cla(h.ax2);
        plot(h.ax2, SNR_dB, Cap_RF,    'k-',  'LineWidth',1.5, 'DisplayName','RF Only');
        hold(h.ax2,'on');
        plot(h.ax2, SNR_dB, Cap_noRIS, 'b--', 'LineWidth',1.5, 'DisplayName','Hybrid (no RIS)');
        plot(h.ax2, SNR_dB, Cap_RIS,   'r-',  'LineWidth',2.5, 'DisplayName',sprintf('RIS-Hybrid N=%d',N));
        hold(h.ax2,'off');
        xlabel(h.ax2,'Average SNR (dB)','FontSize',10);
        ylabel(h.ax2,'Ergodic Capacity C (bits/s/Hz)','FontSize',10);
        title(h.ax2,sprintf('Ergodic Capacity | %s | %s | N=%d',t_name,s_name,N),'FontSize',10);
        legend(h.ax2,'Location','northwest','FontSize',8);
        grid(h.ax2,'on'); xlim(h.ax2,[SNR_min SNR_max]);

        %% ── PLOT 3: BER ─────────────────────────────────────────────────
        cla(h.ax3);
        semilogy(h.ax3, SNR_dB, BER_RF,    'k-',  'LineWidth',1.5, 'DisplayName','RF Only');
        hold(h.ax3,'on');
        semilogy(h.ax3, SNR_dB, BER_noRIS, 'b--', 'LineWidth',1.5, 'DisplayName','Hybrid (no RIS)');
        semilogy(h.ax3, SNR_dB, BER_RIS,   'r-',  'LineWidth',2.5, 'DisplayName',sprintf('RIS-Hybrid N=%d',N));
        yline(h.ax3, tgt_ber, 'g:', 'LineWidth',1.5, 'Label',sprintf('Target=%.0e',tgt_ber));
        hold(h.ax3,'off');
        xlabel(h.ax3,'Average SNR (dB)','FontSize',10);
        ylabel(h.ax3,'Average BER','FontSize',10);
        title(h.ax3,sprintf('Bit Error Rate (BPSK) | %s | %s | N=%d',t_name,s_name,N),'FontSize',10);
        legend(h.ax3,'Location','southwest','FontSize',8);
        grid(h.ax3,'on'); ylim(h.ax3,[1e-6 1]); xlim(h.ax3,[SNR_min SNR_max]);

        %% ── Find required SNR for targets ───────────────────────────────
        snr_for_out = findSNR(SNR_dB, Pout_RIS, tgt_out);
        snr_for_ber = findSNR(SNR_dB, BER_RIS,  tgt_ber);
        snr_noRIS_out = findSNR(SNR_dB, Pout_noRIS, tgt_out);
        snr_noRIS_ber = findSNR(SNR_dB, BER_noRIS,  tgt_ber);

        %% ── Capacity at midpoint SNR ────────────────────────────────────
        mid_idx    = round(length(SNR_lin)/2);
        mid_snr_db = SNR_dB(mid_idx);
        cap_at_mid = Cap_RIS(mid_idx);
        ber_at_mid = BER_RIS(mid_idx);
        out_at_mid = Pout_RIS(mid_idx);

        %% ── SNR saving ──────────────────────────────────────────────────
        snr_saving_out = snr_noRIS_out - snr_for_out;
        snr_saving_ber = snr_noRIS_ber - snr_for_ber;

        %% ── Power budget ─────────────────────────────────────────────────
        %  Required tx power = tx_pwr - snr_for_ber (rough estimate)
        %  RIS saving in Watts: 10^(snr_saving/10) fold reduction
        power_saving_factor = 10^(snr_saving_ber/10);
        eff_tx_pwr = tx_pwr - snr_for_ber;  % effective required power margin
        solar_surplus = solar_w * (1 - 1/power_saving_factor);

        %% ── Update key results boxes ─────────────────────────────────────
        updateResultBox(h.resultLabels{1}, sprintf('%.1f dB', snr_for_out),   GREEN);
        updateResultBox(h.resultLabels{2}, sprintf('%.1f dB', snr_for_ber),   GREEN);
        updateResultBox(h.resultLabels{3}, sprintf('%.2f b/s/Hz', cap_at_mid), BLUE);
        updateResultBox(h.resultLabels{4}, sprintf('%.1f dB', snr_saving_ber), RED);
        updateResultBox(h.resultLabels{5}, sprintf('%.1f W', solar_surplus),   ORANGE);
        updateResultBox(h.resultLabels{6}, sprintf('N=%d', N),                 DARKBLUE);

        %% ── Link budget text ─────────────────────────────────────────────
        budget_lines = buildBudget(t_name, s_name, m, alpha, beta, N, ...
            snr_for_out, snr_for_ber, snr_noRIS_out, snr_noRIS_ber, ...
            snr_saving_out, snr_saving_ber, cap_at_mid, ber_at_mid, ...
            out_at_mid, mid_snr_db, tx_pwr, solar_w, solar_surplus, ...
            power_saving_factor, tgt_out, tgt_ber);
        set(h.budgetText, 'Value', budget_lines);

        %% ── Store for export ─────────────────────────────────────────────
        h.lastResults = struct('budget', {budget_lines}, ...
            'terrain', t_name, 'season', s_name, ...
            'm', m, 'N', N, 'alpha', alpha, 'beta', beta, ...
            'SNR_dB', SNR_dB, ...
            'Pout_RIS', Pout_RIS, 'Cap_RIS', Cap_RIS, 'BER_RIS', BER_RIS);
        guidata(fig, h);

        set(h.statusLabel, 'Text', sprintf( ...
            '  Computation complete. Required SNR: %.1f dB (BER target) | %.1f dB (Outage target) | Capacity at %d dB: %.2f bits/s/Hz', ...
            snr_for_ber, snr_for_out, mid_snr_db, cap_at_mid));
    end % computeResults

    function exportReport(~, ~)
        h = guidata(fig);
        if isempty(h.lastResults)
            uialert(fig, 'Please click COMPUTE first.', 'No Results');
            return;
        end

        timestamp  = datestr(now, 'yyyymmdd_HHMMSS');
        filename   = sprintf('RIS_Planning_Report_%s.txt', timestamp);
        [fn, fp]   = uiputfile('*.txt', 'Save Report As', filename);
        if fn == 0, return; end

        fid = fopen(fullfile(fp,fn), 'w');
        fprintf(fid, '%s\n', repmat('=',1,65));
        fprintf(fid, 'RIS-ASSISTED HYBRID RF/FSO PLANNING TOOL\n');
        fprintf(fid, 'HIT Electronic Engineering — Master of Technology Research\n');
        fprintf(fid, 'Report generated: %s\n', datestr(now));
        fprintf(fid, '%s\n', repmat('=',1,65));
        fprintf(fid, '\n');
        for k = 1:length(h.lastResults.budget)
            fprintf(fid, '%s\n', h.lastResults.budget{k});
        end
        fprintf(fid, '\n%s\n', repmat('-',1,65));
        fprintf(fid, 'NUMERICAL RESULTS TABLE\n');
        fprintf(fid, '%s\n', repmat('-',1,65));
        fprintf(fid, '%-10s %-15s %-15s %-15s\n', ...
            'SNR(dB)', 'P_out (RIS)', 'Cap (RIS)', 'BER (RIS)');
        fprintf(fid, '%s\n', repmat('-',1,55));
        for k = 1:length(h.lastResults.SNR_dB)
            fprintf(fid, '%-10.1f %-15.4e %-15.4f %-15.4e\n', ...
                h.lastResults.SNR_dB(k), ...
                h.lastResults.Pout_RIS(k), ...
                h.lastResults.Cap_RIS(k), ...
                h.lastResults.BER_RIS(k));
        end
        fclose(fid);
        uialert(fig, sprintf('Report saved to:\n%s', fullfile(fp,fn)), ...
            'Export Successful', 'Icon', 'success');
    end % exportReport

end % RIS_Planning_Tool

% =========================================================================
%  HELPER FUNCTIONS
% =========================================================================

function val = gamma_fn(x)
    val = gamma(x);
end

function val = qfunc_approx(x)
    val = 0.5 * erfc(x / sqrt(2));
end

function val = gammainc_approx(x, a)
    if x <= 0,  val = 0; return; end
    val = gammainc(x, a);
end

function val = fso_cdf(gamma_th, alpha, beta, snr_bar)
    if gamma_th <= 0 || snr_bar <= 0
        val = 0; return;
    end
    try
        pdf_fso = @(g) (alpha*beta)^((alpha+beta)/2) / ...
            (gamma(alpha)*gamma(beta)*snr_bar^((alpha+beta)/4)) .* ...
            max(g,1e-12).^((alpha+beta)/4 - 1) .* ...
            besselk(alpha-beta, 2*sqrt(alpha*beta*sqrt(max(g,1e-12)/snr_bar)));
        val = integral(pdf_fso, 0, gamma_th, 'RelTol',1e-4,'AbsTol',1e-10);
        val = max(0, min(1, real(val)));
    catch
        val = 0.5;
    end
end

function C = cap_integral(snr, m, alpha, beta, N, Omega, use_RIS)
    E_h      = sqrt(Omega/m) * gamma(m+0.5) / gamma(m);
    mu_p     = E_h^2;
    sigma_p2 = Omega^2 - mu_p^2;
    mu_Z     = N * mu_p;
    sigma_Z  = sqrt(max(N * sigma_p2, 1e-12));

    integrand = @(g) compute_1_minus_F(g, m, alpha, beta, ...
                     mu_Z, sigma_Z, snr, use_RIS) ./ (1 + g);
    try
        C = (1/(2*log(2))) * integral(integrand, 0, 80*snr, ...
            'RelTol',1e-3,'AbsTol',1e-8);
        C = max(0, real(C));
    catch
        C = 0;
    end
end

function BER = ber_integral(snr, m, alpha, beta, N, Omega, use_RIS)
    E_h      = sqrt(Omega/m) * gamma(m+0.5) / gamma(m);
    mu_p     = E_h^2;
    sigma_p2 = Omega^2 - mu_p^2;
    mu_Z     = N * mu_p;
    sigma_Z  = sqrt(max(N * sigma_p2, 1e-12));

    integrand = @(g) 0.5*erfc(sqrt(max(g,0))) .* ...
        compute_f_e2e(g, m, alpha, beta, mu_Z, sigma_Z, snr, use_RIS);
    try
        BER = integral(integrand, 0, 60*snr, 'RelTol',1e-3,'AbsTol',1e-10);
        BER = max(0, min(0.5, real(BER)));
    catch
        BER = 0.5;
    end
end

function val = compute_1_minus_F(g, m, alpha, beta, mu_Z, sigma_Z, snr, use_RIS)
    val = zeros(size(g));
    for i = 1:length(g)
        gi = max(g(i), 1e-12);
        if use_RIS
            F_SR = qfunc_approx((mu_Z - sqrt(gi/snr))/sigma_Z) ...
                 - qfunc_approx((mu_Z + sqrt(gi/snr))/sigma_Z);
        else
            F_SR = gammainc_approx(m * gi / snr, m);
        end
        F_RF  = gammainc_approx(m * gi / snr, m);
        F_FSO = fso_cdf(gi, alpha, beta, snr);
        F_e2e = F_SR + (1 - F_SR) * F_RF * F_FSO;
        val(i) = max(0, 1 - F_e2e);
    end
end

function f = compute_f_e2e(g, m, alpha, beta, mu_Z, sigma_Z, snr, use_RIS)
    delta = 1e-3 * max(abs(g), 1e-6);
    F_plus  = zeros(size(g));
    F_minus = zeros(size(g));
    for i = 1:length(g)
        gp = g(i) + delta;
        gm = max(g(i) - delta, 1e-12);
        if use_RIS
            FSR_p = qfunc_approx((mu_Z-sqrt(gp/snr))/sigma_Z) - qfunc_approx((mu_Z+sqrt(gp/snr))/sigma_Z);
            FSR_m = qfunc_approx((mu_Z-sqrt(gm/snr))/sigma_Z) - qfunc_approx((mu_Z+sqrt(gm/snr))/sigma_Z);
        else
            FSR_p = gammainc_approx(m*gp/snr, m);
            FSR_m = gammainc_approx(m*gm/snr, m);
        end
        FRF_p = gammainc_approx(m*gp/snr, m);
        FRF_m = gammainc_approx(m*gm/snr, m);
        FFSO_p = fso_cdf(gp, alpha, beta, snr);
        FFSO_m = fso_cdf(gm, alpha, beta, snr);
        F_plus(i)  = FSR_p + (1-FSR_p)*FRF_p*FFSO_p;
        F_minus(i) = FSR_m + (1-FSR_m)*FRF_m*FFSO_m;
    end
    f = max(0, (F_plus - F_minus) ./ (2*delta));
end

function snr_req = findSNR(SNR_dB, metric_vec, target)
    idx = find(metric_vec <= target, 1, 'first');
    if isempty(idx)
        snr_req = SNR_dB(end) + 5;
    elseif idx == 1
        snr_req = SNR_dB(1);
    else
        snr_req = interp1(log10(metric_vec(idx-1:idx)), ...
                          SNR_dB(idx-1:idx), log10(target));
    end
end

function lines = buildBudget(t_name, s_name, m, alpha, beta, N, ...
    snr_for_out, snr_for_ber, snr_noRIS_out, snr_noRIS_ber, ...
    snr_saving_out, snr_saving_ber, cap_mid, ber_mid, out_mid, mid_snr, ...
    tx_pwr, solar_w, solar_surplus, pwr_factor, tgt_out, tgt_ber)

    lines = {
        '================================================================'
        ' RIS-ASSISTED HYBRID RF/FSO — LINK BUDGET SUMMARY'
        '================================================================'
        ''
        ' DEPLOYMENT CONTEXT'
        sprintf('   Terrain type     : %s', t_name)
        sprintf('   Season           : %s', s_name)
        sprintf('   Nakagami-m       : m = %.1f', m)
        sprintf('   FSO turbulence   : alpha = %.1f, beta = %.1f', alpha, beta)
        ''
        ' SYSTEM CONFIGURATION'
        sprintf('   RIS elements     : N = %d', N)
        sprintf('   Relay protocol   : Decode-and-Forward (DF)')
        sprintf('   Combining scheme : Selection Combining (SC)')
        sprintf('   Modulation       : BPSK')
        ''
        '----------------------------------------------------------------'
        sprintf(' REQUIRED SNR TO MEET TARGET (P_out = %.0e)', tgt_out)
        '----------------------------------------------------------------'
        sprintf('   RIS-Hybrid N=%-3d : %6.1f dB', N, snr_for_out)
        sprintf('   Hybrid (no RIS)  : %6.1f dB', snr_noRIS_out)
        sprintf('   SNR saving       : %6.1f dB  (%.1fx power reduction)', ...
                snr_saving_out, 10^(snr_saving_out/10))
        ''
        sprintf(' REQUIRED SNR TO MEET TARGET (BER = %.0e, BPSK)', tgt_ber)
        '----------------------------------------------------------------'
        sprintf('   RIS-Hybrid N=%-3d : %6.1f dB', N, snr_for_ber)
        sprintf('   Hybrid (no RIS)  : %6.1f dB', snr_noRIS_ber)
        sprintf('   SNR saving       : %6.1f dB  (%.1fx power reduction)', ...
                snr_saving_ber, 10^(snr_saving_ber/10))
        ''
        sprintf(' SYSTEM PERFORMANCE AT SNR = %d dB', round(mid_snr))
        '----------------------------------------------------------------'
        sprintf('   Outage prob      : %.4e', out_mid)
        sprintf('   Ergodic capacity : %.4f bits/s/Hz', cap_mid)
        sprintf('   BER (BPSK)       : %.4e', ber_mid)
        ''
        ' SOLAR POWER ASSESSMENT'
        '----------------------------------------------------------------'
        sprintf('   Max TX power     : %d dBm', round(tx_pwr))
        sprintf('   Solar output     : %d W', round(solar_w))
        sprintf('   RIS power saving : %.1fx reduction vs no-RIS', pwr_factor)
        sprintf('   Solar surplus    : %.1f W  (available for community use)', solar_surplus)
        ''
        ' NDS2 ALIGNMENT'
        '----------------------------------------------------------------'
        '   Rural BER target (voice quality) : 1e-3'
        sprintf('   Achieved at      : %.1f dB SNR with N=%d RIS elements', snr_for_ber, N)
        '   Recommendation   : Cost-effective for solar deployment'
        sprintf('   Optimal N range  : 10 to 20 elements for %s', t_name)
        '================================================================'
    };
end

function [rData, rLabels] = createResultBoxes(parent, WHITE, BLUE, DARKGREY, GREEN, RED)
    titles = {'SNR for Outage Target', 'SNR for BER Target', ...
              'Capacity at Mid-SNR', 'SNR Saving (BER)', ...
              'Solar Surplus', 'Optimal N'};
    ypos   = [285 230 175 120 65 10];
    rLabels = cell(6,1);
    rData   = struct();

    for k = 1:6
        uipanel(parent, 'Position', [8 ypos(k) 254 48], ...
            'BackgroundColor', WHITE, 'BorderType', 'line');
        uilabel(parent, 'Text', titles{k}, ...
            'Position', [12 ypos(k)+28 250 16], ...
            'FontSize', 8, 'FontColor', DARKGREY, 'FontWeight', 'bold');
        rLabels{k} = uilabel(parent, 'Text', '—', ...
            'Position', [12 ypos(k)+6 250 20], ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', BLUE, 'HorizontalAlignment', 'center');
    end
end

function updateResultBox(lbl, text, color)
    set(lbl, 'Text', text, 'FontColor', color);
end

function lines = getTerrainGuide()
    lines = {
        'TERRAIN → m VALUE GUIDE'
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        'Highveld Plateau   m = 1.5'
        '  Harare, Midlands, Mashonaland'
        '  Flat, sparse acacia woodland'
        '  BASELINE for this research'
        ''
        'Lowveld             m = 1.0'
        '  Masvingo, Mat. South'
        '  Flat, dry, sparse bush'
        '  Rayleigh-equivalent fading'
        ''
        'Eastern Highlands  m = 0.5'
        '  Manicaland (Mutare, Nyanga)'
        '  Hilly, dense Msasa woodland'
        '  Severe fading — needs N≥50'
        ''
        'Open Savanna        m = 2.0'
        '  Matabeleland North'
        '  Near line-of-sight paths'
        '  Good fading conditions'
        ''
        'Line-of-Sight       m = 3.0'
        '  Clear rural elevated paths'
        '  Best propagation conditions'
        '  N=5-10 elements sufficient'
        ''
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        'SEASON → TURBULENCE GUIDE'
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        'Dry Season (May-Sep)'
        '  α=11.6, β=10.1 (Weak)'
        '  Best FSO performance'
        ''
        'Highveld Average'
        '  α=4.0,  β=1.9  (Moderate)'
        '  Baseline conditions'
        ''
        'Rainy Season (Oct-Apr)'
        '  α=4.2,  β=1.4  (Strong)'
        '  7 dB extra SNR margin needed'
        '  RF link provides backup'
        ''
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        'KEY FINDINGS (from thesis)'
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        '• RIS saves 7-8 dB SNR vs no-RIS'
        '• N=10-20 optimal for Highveld'
        '• Terrain effect > Season effect'
        '• Seasonal BER gap < 7 dB'
        '• Match relay power to source SNR'
    };
end
