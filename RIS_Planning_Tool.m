function varargout = RIS_Planning_Tool(varargin)
% =========================================================================
% RIS_Planning_Tool.m                                        Version 1.2.0
% =========================================================================
% Deployment planning tool for RIS-assisted hybrid RF/FSO relay links,
% with terrain and season presets for rural Zimbabwe.
%
% Authors : T. Mzembi, M. C. Rushambwa (Harare Institute of Technology)
% Licence : MIT
%
% USAGE
%   RIS_Planning_Tool                  open the graphical planning tool
%   RIS_Planning_Tool('selftest')      numerical self-test of the engine
%   RIS_Planning_Tool('validate')      Monte Carlo check of the engine
%   RIS_Planning_Tool('validate',P,n)  ... for parameters P, n samples
%   RIS_Planning_Tool('benchmark')     run-time scaling table
%   P = RIS_Planning_Tool('defaults')  default parameter structure
%   R = RIS_Planning_Tool(P)           batch run without the window
%
% IN THE WINDOW
%   1. Choose terrain and season (or "Custom" to type m, alpha, beta)
%   2. Set N, the SNR sweep and the outage / BER targets
%   3. On the "Link budget" tab enter frequency, hop distance, bandwidth,
%      noise figure, antenna gains and the transmit-power budget
%   4. Click COMPUTE RESULTS, then EXPORT REPORT to save a text report
%
% REQUIREMENTS: MATLAB R2018b or later, no toolboxes.
%
% SYSTEM MODEL
%   Source -> RIS (N elements) -> DF relay -> destination. Hop 1 is RF
%   (Nakagami-m; coherent RIS combining, central-limit approximation).
%   Hop 2 is parallel RF (Nakagami-m) and FSO (Gamma-Gamma, IM/DD) with
%   selection combining. Every link is referred to one average SNR
%   (normalised model); the RIS-path excess loss and the fog margin are
%   deterministic offsets on the first hop and on the FSO branch.
%
% CHANGE LOG
%   v1.2.0
%   - FIX: the BER routine of v1.0/v1.1 raised an internal error on every
%     call (vector/scalar indexing in the finite-difference derivative)
%     and silently returned 0.5. BER is now computed from the end-to-end
%     CDF without numerical differentiation:
%         BER = (1/sqrt(pi)) * int_0^inf exp(-u^2) F(u^2) du      (BPSK)
%   - FIX: a target that is not reached inside the SNR sweep is reported
%     as "not met" instead of the placeholder value (max SNR + 5 dB).
%   - FIX: no silent fall-back values; numerical problems are reported.
%   - NEW: link budget. Required average SNR is converted to required
%     transmit power from frequency, hop distance, bandwidth, noise
%     figure and antenna gains, and checked against the power budget.
%     The former "solar surplus" figure is replaced by the amplifier DC
%     power actually saved.
%   - NEW: user-defined channel parameters (Custom m, alpha, beta).
%   - NEW: implementation margin and RIS-path excess loss (both 0 dB by
%     default, which reproduces the normalised best-case model).
%   - NEW: recommended N is computed (smallest N within 0.5 dB of N=100
%     at the outage target) instead of being a fixed text.
%   - NEW: validity notes in the summary (CLT range, first-hop share).
%   - NEW: 'selftest', 'validate' (Monte Carlo), 'benchmark', batch mode.
%   - CHANGE: Gamma-Gamma CDF is tabulated once per run on a logarithmic
%     irradiance grid (fixed Gauss-Legendre rule), so run time no longer
%     depends on nested adaptive quadrature.
%   - CHANGE: fog margin uses the hop distance from the link budget (was
%     a fixed 1 km) and is applied as 2 x optical attenuation to the
%     electrical SNR of the IM/DD FSO branch.
%   - CHANGE: start-up season is the moderate-turbulence baseline.
%   v1.1  optional fog/visibility margin (Kim et al., 2001); smaller window
%   v1.0  first release
% =========================================================================

    if nargin == 0
        launch_gui();
        return;
    end

    arg = varargin{1};
    if isstruct(arg)
        varargout{1} = ris_compute(fill_defaults(arg));
        return;
    end
    if ~ischar(arg)
        error('RIS_Planning_Tool:input', ...
              'Argument must be a parameter structure or a mode name.');
    end

    switch lower(arg)
        case 'defaults'
            varargout{1} = default_params();
        case 'version'
            varargout{1} = tool_version();
        case 'selftest'
            ok = run_selftest();
            if nargout > 0, varargout{1} = ok; end
        case 'validate'
            V = run_validation(varargin{2:end});
            if nargout > 0, varargout{1} = V; end
        case 'benchmark'
            B = run_benchmark();
            if nargout > 0, varargout{1} = B; end
        otherwise
            error('RIS_Planning_Tool:input', ...
                  'Unknown mode "%s". Use selftest, validate, benchmark or defaults.', arg);
    end
end

function v = tool_version()
    v = '1.2.0';
end

% =========================================================================
%  PARAMETERS AND PRESET TABLES
% =========================================================================

function P = default_params()
    % Channel
    P.terrain       = 'Highveld';
    P.m             = 1.5;      % Nakagami-m, all RF links
    P.season        = 'Highveld Average';
    P.alpha         = 4.0;      % Gamma-Gamma large-scale parameter
    P.beta          = 1.9;      % Gamma-Gamma small-scale parameter
    P.custom_m      = false;
    P.custom_ab     = false;
    P.fog_on        = false;
    P.visibility_km = 2;        % used only when fog_on is true
    P.lambda_nm     = 1550;     % FSO wavelength for the fog model
    % System
    P.N             = 50;       % RIS elements
    P.SNR_min       = -10;      % dB, sweep is in 1 dB steps
    P.SNR_max       = 30;       % dB
    P.gamma_th      = 1;        % outage threshold (linear)
    P.tgt_out       = 1e-3;     % target outage probability
    P.tgt_ber       = 1e-3;     % target BER (BPSK)
    % Link budget (RF, per hop)
    P.f_GHz         = 2.4;      % carrier frequency
    P.d_km          = 5;        % hop distance (also the FSO range for fog)
    P.B_MHz         = 20;       % noise bandwidth
    P.NF_dB         = 7;        % receiver noise figure
    P.G_dBi         = 20;       % transmit + receive antenna gain
    P.margin_dB     = 0;        % implementation margin
    P.L_ris_dB      = 0;        % RIS-path excess loss (0 = normalised model)
    % Power
    P.tx_max_dBm    = 20;       % transmit-power budget
    P.pa_eff        = 25;       % power-amplifier efficiency, percent
    P.solar_w       = 50;       % solar panel output, W
end

function P = fill_defaults(Pin)
    P = default_params();
    f = fieldnames(Pin);
    for k = 1:numel(f)
        P.(f{k}) = Pin.(f{k});
    end
end

function T = terrain_table()
    % Terrain presets: the single place where terrain -> Nakagami-m is set.
    T = struct( ...
        'label', {'Highveld Plateau (m = 1.5) — Harare, Midlands', ...
                  'Lowveld (m = 1.0) — Masvingo, Mat. South', ...
                  'Eastern Highlands (m = 0.5) — Manicaland', ...
                  'Open Savanna (m = 2.0) — Matabeleland North', ...
                  'Line-of-Sight Path (m = 3.0) — Clear rural'}, ...
        'name',  {'Highveld', 'Lowveld', 'E.Highlands', 'Open Savanna', 'LOS'}, ...
        'm',     {1.5, 1.0, 0.5, 2.0, 3.0});
end

function S = season_table()
    % Season presets: the single place where season -> (alpha, beta) is set.
    S = struct( ...
        'label', {'Dry Season — Weak turbulence (α=11.6, β=10.1)', ...
                  'Highveld Average — Moderate turbulence (α=4.0, β=1.9)', ...
                  'Rainy Season — Strong turbulence (α=4.2, β=1.4)'}, ...
        'name',  {'Dry Season', 'Highveld Average', 'Rainy Season'}, ...
        'alpha', {11.6, 4.0, 4.2}, ...
        'beta',  {10.1, 1.9, 1.4});
end

function check_params(P)
    if ~(P.m >= 0.5 && P.m <= 10)
        error('RIS_Planning_Tool:param', 'Nakagami m must lie between 0.5 and 10.');
    end
    if ~(P.alpha >= 1 && P.alpha <= 30 && P.beta >= 1 && P.beta <= 30)
        error('RIS_Planning_Tool:param', 'Gamma-Gamma alpha and beta must lie between 1 and 30.');
    end
    if ~(P.N >= 1 && P.N == round(P.N))
        error('RIS_Planning_Tool:param', 'N must be a positive integer.');
    end
    if ~(P.SNR_max > P.SNR_min)
        error('RIS_Planning_Tool:param', 'Max SNR must exceed Min SNR.');
    end
    if ~(P.gamma_th > 0 && P.tgt_out > 0 && P.tgt_out < 1 && P.tgt_ber > 0 && P.tgt_ber < 0.5)
        error('RIS_Planning_Tool:param', 'Threshold and targets must be positive (targets below 1 and 0.5).');
    end
    if ~(P.f_GHz > 0 && P.d_km > 0 && P.B_MHz > 0 && P.pa_eff > 0 && P.pa_eff <= 100)
        error('RIS_Planning_Tool:param', 'Frequency, distance, bandwidth and PA efficiency must be positive.');
    end
    if ~(P.L_ris_dB >= 0 && P.margin_dB >= 0)
        error('RIS_Planning_Tool:param', 'Implementation margin and RIS excess loss cannot be negative.');
    end
    if P.fog_on && ~(P.visibility_km > 0)
        error('RIS_Planning_Tool:param', 'Visibility must be positive.');
    end
end

% =========================================================================
%  ANALYTICAL ENGINE
% =========================================================================

function R = ris_compute(P)
    % Complete analysis for one parameter set. No graphics.
    t_start = tic;
    check_params(P);

    SNR_dB = P.SNR_min:1:P.SNR_max;
    snr    = 10.^(SNR_dB/10);
    nP     = numel(snr);

    % ── Deterministic offsets ────────────────────────────────────────────
    fog.on = logical(P.fog_on);
    if fog.on
        fog.dB_per_km  = fog_attenuation(P.visibility_km, P.lambda_nm);
        fog.optical_dB = fog.dB_per_km * P.d_km;
    else
        fog.dB_per_km  = 0;
        fog.optical_dB = 0;
    end
    % IM/DD: photocurrent follows optical power, so electrical SNR falls by
    % twice the optical attenuation expressed in dB.
    fog.electrical_dB = 2 * fog.optical_dB;

    S.m     = P.m;
    S.k_fso = 10^(-fog.electrical_dB/10);   % FSO branch SNR factor
    S.k_ris = 10^(-P.L_ris_dB/10);          % RIS first-hop SNR factor
    [S.mu_Z, S.sigma_Z] = ris_moments(P.m, P.N);
    S.T     = gg_cdf_table(P.alpha, P.beta);

    % ── Sweep ────────────────────────────────────────────────────────────
    z = zeros(1, nP);
    Pout_RIS = z; Pout_noRIS = z; Pout_RF = z;
    Cap_RIS  = z; Cap_noRIS  = z; Cap_RF  = z;
    BER_RIS  = z; BER_noRIS  = z; BER_RF  = z;
    F2_th    = z;    % second-hop outage at the threshold (reused for N search)

    for i = 1:nP
        g   = snr(i);
        xth = P.gamma_th / g;

        F2_th(i)      = cdf_hop2(xth, S);
        Pout_RIS(i)   = cdf_e2e(xth, S, 1);
        Pout_noRIS(i) = cdf_e2e(xth, S, 0);
        Pout_RF(i)    = cdf_nak(xth, P.m);

        Cap_RIS(i)    = cap_e2e(g, S, 1);
        Cap_noRIS(i)  = cap_e2e(g, S, 0);
        Cap_RF(i)     = cap_rf(g, P.m);

        BER_RIS(i)    = ber_e2e(g, S, 1);
        BER_noRIS(i)  = ber_e2e(g, S, 0);
        BER_RF(i)     = ber_rf(g, P.m);
    end

    % ── Required SNR for the targets ─────────────────────────────────────
    q = struct();
    [q.out_ris,  q.out_ris_st]  = find_req(SNR_dB, Pout_RIS,   P.tgt_out);
    [q.out_no,   q.out_no_st]   = find_req(SNR_dB, Pout_noRIS, P.tgt_out);
    [q.out_rf,   q.out_rf_st]   = find_req(SNR_dB, Pout_RF,    P.tgt_out);
    [q.ber_ris,  q.ber_ris_st]  = find_req(SNR_dB, BER_RIS,    P.tgt_ber);
    [q.ber_no,   q.ber_no_st]   = find_req(SNR_dB, BER_noRIS,  P.tgt_ber);
    [q.ber_rf,   q.ber_rf_st]   = find_req(SNR_dB, BER_RF,     P.tgt_ber);

    [q.save_out, q.save_out_kind] = snr_saving(q.out_no, q.out_no_st, q.out_ris, q.out_ris_st, P.SNR_max);
    [q.save_ber, q.save_ber_kind] = snr_saving(q.ber_no, q.ber_no_st, q.ber_ris, q.ber_ris_st, P.SNR_max);

    % Governing requirement: both targets must hold.
    [q.gov_ris, q.gov_ris_by] = governing(q.out_ris, q.ber_ris);
    [q.gov_no,  q.gov_no_by]  = governing(q.out_no,  q.ber_no);

    % ── Link budget: average SNR <-> transmit power ──────────────────────
    LB.L_path_dB  = 92.45 + 20*log10(P.f_GHz) + 20*log10(P.d_km);   % free space
    LB.noise_dBm  = -174 + 10*log10(P.B_MHz*1e6) + P.NF_dB;
    LB.offset_dB  = P.margin_dB + LB.L_path_dB - P.G_dBi + LB.noise_dBm;
    LB.snr_at_pmax = P.tx_max_dBm - LB.offset_dB;     % average SNR at full power
    LB.ptx_ris    = q.gov_ris + LB.offset_dB;         % dBm, NaN if target not met
    LB.ptx_no     = q.gov_no  + LB.offset_dB;
    LB.margin_ris = P.tx_max_dBm - LB.ptx_ris;
    LB.margin_no  = P.tx_max_dBm - LB.ptx_no;
    LB.ok_ris     = isfinite(LB.margin_ris) && LB.margin_ris >= 0;
    LB.ok_no      = isfinite(LB.margin_no)  && LB.margin_no  >= 0;

    % ── Power: what the SNR saving is worth at the amplifier ─────────────
    eta = P.pa_eff / 100;
    PW.ptx_ris_W = 10^((LB.ptx_ris - 30)/10);
    PW.ptx_no_W  = 10^((LB.ptx_no  - 30)/10);
    PW.pdc_ris_W = PW.ptx_ris_W / eta;
    PW.pdc_no_W  = PW.ptx_no_W  / eta;
    if LB.ok_ris && LB.ok_no
        PW.saved_W   = PW.pdc_no_W - PW.pdc_ris_W;
        PW.saved_pct = 100 * PW.saved_W / P.solar_w;
    else
        PW.saved_W   = NaN;
        PW.saved_pct = NaN;
    end

    % ── Recommended array size (outage target) ───────────────────────────
    NR = recommend_N(SNR_dB, snr, F2_th, P);

    % ── Mid-sweep operating point ────────────────────────────────────────
    mid_idx   = round(nP/2);
    MID.snr_dB = SNR_dB(mid_idx);
    MID.out    = Pout_RIS(mid_idx);
    MID.cap    = Cap_RIS(mid_idx);
    MID.ber    = BER_RIS(mid_idx);

    % ── Validity notes ───────────────────────────────────────────────────
    notes = {};
    notes{end+1} = ['Best-case figures: perfect CSI and continuous phase control at the RIS, ', ...
                    'ideal DF relay, no FSO pointing error. Budget for these with the implementation margin.'];
    notes{end+1} = 'All links are referred to one average SNR (normalised model); the link budget uses one hop distance.';
    if P.N < 20
        notes{end+1} = sprintf('N = %d is below 20: the central-limit model of the RIS hop is indicative only.', P.N);
    end
    % Share of the RIS hop in outage / BER at the required SNR. The Gaussian
    % (central-limit) tail overstates this share, so a large share means the
    % required SNR is on the conservative side.
    share_out = 0;  share_ber = 0;
    if q.out_ris_st == 0
        g_req = 10^(q.out_ris/10);
        share_out = cdf_ris(P.gamma_th / g_req, S.mu_Z, S.sigma_Z, S.k_ris) / P.tgt_out;
    end
    if q.ber_ris_st == 0
        g_req = 10^(q.ber_ris/10);
        share_ber = integral(@(u) exp(-u.^2) .* cdf_ris(u.^2 ./ g_req, S.mu_Z, S.sigma_Z, S.k_ris), 0, 6.5, ...
                             'RelTol', 1e-6, 'AbsTol', 1e-20) / sqrt(pi) / P.tgt_ber;
    end
    if max(share_out, share_ber) > 0.2
        notes{end+1} = sprintf(['At the required SNR the RIS hop accounts for %.0f%% of the outage and %.0f%% of the BER. ', ...
            'The Gaussian tail of the central-limit model overstates these, so the required SNR is conservative here.'], ...
            100*min(share_out, 1), 100*min(share_ber, 1));
    end
    if q.out_ris_st == -1 || q.ber_ris_st == -1
        notes{end+1} = sprintf('A target is not met by the RIS-assisted system up to %g dB. Raise Max SNR to look further.', P.SNR_max);
    end
    if P.custom_m || P.custom_ab
        notes{end+1} = 'User-defined channel parameters are in use (not a terrain/season preset).';
    end
    if fog.on
        notes{end+1} = sprintf(['Fog margin: %.2f dB/km optical at %g nm over %.2f km = %.1f dB optical, ', ...
            'applied as %.1f dB to the electrical SNR of the IM/DD FSO branch.'], ...
            fog.dB_per_km, P.lambda_nm, P.d_km, fog.optical_dB, fog.electrical_dB);
    end
    if P.L_ris_dB > 0
        notes{end+1} = sprintf('RIS-path excess loss of %.1f dB applied to the first hop.', P.L_ris_dB);
    end
    if abs(S.T.norm - 1) > 1e-6
        notes{end+1} = sprintf('Numerical warning: Gamma-Gamma CDF table normalises to %.8f instead of 1.', S.T.norm);
    end
    nbad = sum(~isfinite([Pout_RIS Pout_noRIS Cap_RIS Cap_noRIS BER_RIS BER_noRIS]));
    if nbad > 0
        notes{end+1} = sprintf('Numerical warning: %d result value(s) are not finite.', nbad);
    end

    % ── Pack ─────────────────────────────────────────────────────────────
    R.version = tool_version();
    R.P = P;
    R.SNR_dB = SNR_dB;
    R.Pout_RIS = Pout_RIS; R.Pout_noRIS = Pout_noRIS; R.Pout_RF = Pout_RF;
    R.Cap_RIS  = Cap_RIS;  R.Cap_noRIS  = Cap_noRIS;  R.Cap_RF  = Cap_RF;
    R.BER_RIS  = BER_RIS;  R.BER_noRIS  = BER_noRIS;  R.BER_RF  = BER_RF;
    R.req = q; R.lb = LB; R.pw = PW; R.nrec = NR; R.mid = MID; R.fog = fog;
    R.ris_share = [share_out, share_ber];
    R.notes = notes;
    R.elapsed_s = toc(t_start);
end

% ── First hop ────────────────────────────────────────────────────────────

function [mu_Z, sigma_Z] = ris_moments(m, N)
    % Mean and standard deviation of Z = sum_i |h_i||g_i|, unit-power
    % Nakagami-m amplitudes, N elements, coherent combining.
    E_h      = exp(gammaln(m + 0.5) - gammaln(m)) / sqrt(m);   % E|h|
    mu_p     = E_h^2;
    sigma_p2 = 1 - mu_p^2;
    mu_Z     = N * mu_p;
    sigma_Z  = sqrt(max(N * sigma_p2, 1e-12));
end

function F = cdf_ris(x, mu_Z, sigma_Z, k_ris)
    % CDF of the RIS first-hop SNR at gamma = x * (average SNR); CLT model.
    r = sqrt(max(x, 0) ./ k_ris);
    F = q_gauss((mu_Z - r) ./ sigma_Z) - q_gauss((mu_Z + r) ./ sigma_Z);
    F = min(max(F, 0), 1);
end

function F = cdf_nak(x, m)
    % CDF of a unit-mean Nakagami-m SNR at gamma = x * (average SNR).
    F = gammainc(m .* max(x, 0), m);
end

function q = q_gauss(x)
    q = 0.5 * erfc(x ./ sqrt(2));
end

% ── Second hop and end-to-end ────────────────────────────────────────────

function F2 = cdf_hop2(x, S)
    % Selection combining of parallel RF and FSO: both must be below.
    F2 = cdf_nak(x, S.m) .* gg_cdf_eval(S.T, sqrt(max(x, 0) ./ S.k_fso));
end

function F = cdf_e2e(x, S, with_ris)
    % End-to-end SNR CDF of the DF chain at gamma = x * (average SNR).
    if with_ris
        F1 = cdf_ris(x, S.mu_Z, S.sigma_Z, S.k_ris);
    else
        F1 = cdf_nak(x, S.m);
    end
    F2 = cdf_hop2(x, S);
    F  = F1 + (1 - F1) .* F2;
    F  = min(max(F, 0), 1);
end

function C = cap_e2e(g, S, with_ris)
    % Ergodic capacity, bits/s/Hz, half-duplex dual hop:
    %   C = 1/(2 ln 2) * int_0^inf (1 - F(gamma)) / (1 + gamma) dgamma.
    % Evaluated in s, with ln(1 + gamma) = s^2, which removes the square-root
    % behaviour of the CDF at the origin.
    s_max = sqrt(log1p(1e4 * g));
    C = integral(@(s) 2*s .* (1 - cdf_e2e(expm1(s.^2) ./ g, S, with_ris)), 0, s_max, ...
                 'RelTol', 1e-6, 'AbsTol', 1e-10) / (2*log(2));
end

function C = cap_rf(g, m)
    % RF-only baseline, same half-rate convention as the hybrid systems
    % (kept from v1.0/v1.1).
    s_max = sqrt(log1p(200 * g));
    C = integral(@(s) 2*s .* (1 - cdf_nak(expm1(s.^2) ./ g, m)), 0, s_max, ...
                 'RelTol', 1e-6, 'AbsTol', 1e-10) / (2*log(2));
end

function B = ber_e2e(g, S, with_ris)
    % Average BPSK bit error rate from the end-to-end CDF:
    %   BER = (1/sqrt(pi)) * int_0^inf exp(-u^2) F(u^2) du.
    % exp(-6.5^2) is about 4e-19, so the upper limit 6.5 loses nothing.
    B = integral(@(u) exp(-u.^2) .* cdf_e2e(u.^2 ./ g, S, with_ris), 0, 6.5, ...
                 'RelTol', 1e-6, 'AbsTol', 1e-20) / sqrt(pi);
end

function B = ber_rf(g, m)
    % Single-hop Nakagami-m BPSK (moment-generating-function form).
    B = integral(@(phi) (1 + g ./ (m * sin(phi).^2)).^(-m), 0, pi/2, ...
                 'RelTol', 1e-8, 'AbsTol', 1e-20) / pi;
end

% ── Gamma-Gamma irradiance CDF, tabulated once per run ───────────────────

function T = gg_cdf_table(alpha, beta)
    % F_I(I) on a logarithmic irradiance grid, 1e-10 ... 1e3, 64 points per
    % decade. Each cell is integrated with an 8-point Gauss-Legendre rule in
    % t = ln(I); the start value comes from the local power law of the PDF.
    per_dec = 64;  lo = -10;  hi = 3;
    t = linspace(lo*log(10), hi*log(10), (hi - lo)*per_dec + 1);

    xg = [-0.9602898564975363 -0.7966664774136267 -0.5255324099163290 -0.1834346424956498 ...
           0.1834346424956498  0.5255324099163290  0.7966664774136267  0.9602898564975363].';
    wg = [ 0.1012285362903763  0.2223810344533745  0.3137066458778873  0.3626837833783620 ...
           0.3626837833783620  0.3137066458778873  0.2223810344533745  0.1012285362903763];

    a  = t(1:end-1);  b = t(2:end);
    hw = (b - a)/2;   c = (b + a)/2;
    tt = repmat(c, 8, 1) + xg * hw;              % 8 x K nodes
    ft = gg_pdf_logI(tt, alpha, beta);
    ft(~isfinite(ft)) = 0;
    cells = hw .* (wg * ft);                     % 1 x K cell integrals

    % Mass below the first grid point: PDF ~ exp(s t)  =>  F = PDF / s.
    dt = 1e-3;
    f0 = gg_pdf_logI(t(1), alpha, beta);
    f1 = gg_pdf_logI(t(1) + dt, alpha, beta);
    if f0 > 0 && f1 > f0 && isfinite(f1)
        F0 = f0 / ((log(f1) - log(f0)) / dt);
    else
        F0 = 0;
    end

    F = F0 + [0, cumsum(cells)];
    T.norm = F(end);                 % should equal 1; reported if it does not
    F = min(F ./ F(end), 1);

    ok = find(F > 0);
    k0 = ok(1);
    T.t     = t(k0:end);
    T.logF  = log(F(k0:end));
    T.slope = (T.logF(2) - T.logF(1)) / (T.t(2) - T.t(1));   % lower-tail exponent
    T.pp    = pchip(T.t, T.logF);                            % built once, reused
end

function ft = gg_pdf_logI(t, alpha, beta)
    % Gamma-Gamma irradiance PDF times I, as a function of t = ln(I):
    %   f_I(I) = 2 (ab)^((a+b)/2) / (G(a) G(b)) * I^((a+b)/2 - 1) * K_{a-b}(2 sqrt(ab I)).
    % Scaled Bessel function and logarithms keep it finite at both ends.
    zb   = 2 * sqrt(alpha * beta * exp(t));
    logC = log(2) + ((alpha + beta)/2) * log(alpha * beta) - gammaln(alpha) - gammaln(beta);
    ft   = exp(logC + ((alpha + beta)/2) .* t - zb) .* besselk(abs(alpha - beta), zb, 1);
end

function F = gg_cdf_eval(T, I)
    % Interpolates the table (log-log, shape preserving).
    F  = zeros(size(I));
    t  = log(max(I, realmin));
    lo = t <  T.t(1);
    hi = t >= T.t(end);
    md = ~lo & ~hi;
    if any(md(:))
        F(md) = exp(ppval(T.pp, t(md)));
    end
    F(lo) = exp(T.logF(1) + T.slope * (t(lo) - T.t(1)));
    F(hi) = 1;
    F = min(max(F, 0), 1);
end

% ── Fog ──────────────────────────────────────────────────────────────────

function a_dB_per_km = fog_attenuation(V_km, lambda_nm)
    % Specific optical attenuation from visibility: Kim, McArthur and
    % Korevaar, Proc. SPIE 4214 (2001) 26-37.
    %   a (dB/km) = (3.91 / V) * (lambda / 550 nm)^(-q)
    V = max(V_km, 0.05);
    if V > 50
        qk = 1.6;
    elseif V > 6
        qk = 1.3;
    elseif V > 1
        qk = 0.16*V + 0.34;
    elseif V > 0.5
        qk = V - 0.5;
    else
        qk = 0;
    end
    a_dB_per_km = (3.91 / V) * (lambda_nm / 550)^(-qk);
end

% =========================================================================
%  DECISION LAYER
% =========================================================================

function [snr_req, status] = find_req(SNR_dB, metric, target)
    % Lowest average SNR at which metric <= target, by log-linear
    % interpolation on the sweep.
    %   status  0 : found inside the sweep
    %   status  1 : already met at the lowest SNR (value is an upper bound)
    %   status -1 : not met anywhere in the sweep (value is NaN)
    idx = find(metric <= target, 1, 'first');
    if isempty(idx)
        snr_req = NaN;  status = -1;
    elseif idx == 1
        snr_req = SNR_dB(1);  status = 1;
    else
        y = log10(max(metric(idx-1:idx), realmin));
        if y(1) == y(2)
            snr_req = SNR_dB(idx);
        else
            snr_req = SNR_dB(idx-1) + (log10(target) - y(1)) / (y(2) - y(1)) * (SNR_dB(idx) - SNR_dB(idx-1));
        end
        status = 0;
    end
end

function [val, kind] = snr_saving(req_no, st_no, req_ris, st_ris, SNR_max)
    % kind 'eq' : both systems meet the target, val is the saving
    % kind 'lb' : only the RIS system meets it, val is a lower bound
    % kind 'na' : the RIS system does not meet it
    if st_ris == -1
        val = NaN;  kind = 'na';
    elseif st_no == -1
        val = SNR_max - req_ris;  kind = 'lb';
    else
        val = req_no - req_ris;  kind = 'eq';
    end
end

function [g, by] = governing(req_out, req_ber)
    if ~isfinite(req_out) || ~isfinite(req_ber)
        g = NaN;  by = 'target not met';
    elseif req_out >= req_ber
        g = req_out;  by = 'outage target';
    else
        g = req_ber;  by = 'BER target';
    end
end

function NR = recommend_N(SNR_dB, snr, F2_th, P)
    % Smallest N whose outage-target SNR is within 0.5 dB of the N = 100
    % value. Only the first-hop term depends on N, so this costs nothing.
    NR.grid = [5 10 15 20 30 40 50 75 100];
    NR.tol_dB = 0.5;
    NR.req = nan(size(NR.grid));
    k_ris = 10^(-P.L_ris_dB/10);
    xth = P.gamma_th ./ snr;
    for k = 1:numel(NR.grid)
        [mu_Z, sigma_Z] = ris_moments(P.m, NR.grid(k));
        F1 = cdf_ris(xth, mu_Z, sigma_Z, k_ris);
        NR.req(k) = find_req(SNR_dB, F1 + (1 - F1).*F2_th, P.tgt_out);
    end
    ref = NR.req(end);
    if isfinite(ref)
        NR.N = NR.grid(find(NR.req <= ref + NR.tol_dB, 1, 'first'));
    else
        NR.N = NaN;
    end
end

% =========================================================================
%  TEXT OUTPUT
% =========================================================================

function s = fmt_req(val, st, P)
    if st == -1
        s = sprintf('> %g dB (not met in sweep)', P.SNR_max);
    elseif st == 1
        s = sprintf('<= %g dB', P.SNR_min);
    else
        s = sprintf('%.1f dB', val);
    end
end

function s = fmt_saving(val, kind)
    switch kind
        case 'eq'
            s = sprintf('%.1f dB  (%.1fx power)', val, 10^(val/10));
        case 'lb'
            s = sprintf('> %.1f dB  (no-RIS system misses the target in the sweep)', val);
        otherwise
            s = 'n/a  (RIS system misses the target in the sweep)';
    end
end

function lines = build_summary(R)
    P = R.P;  q = R.req;  LB = R.lb;  PW = R.pw;  NR = R.nrec;
    rule1 = repmat('=', 1, 68);
    rule2 = repmat('-', 1, 68);

    if R.fog.on
        fog_line = sprintf('   Fog margin (FSO) : ON   visibility %.2f km -> %.1f dB electrical', ...
                           P.visibility_km, R.fog.electrical_dB);
    else
        fog_line = '   Fog margin (FSO) : OFF';
    end

    L = {};
    L{end+1} = rule1;
    L{end+1} = sprintf(' RIS-ASSISTED HYBRID RF/FSO - LINK BUDGET SUMMARY      (tool v%s)', R.version);
    L{end+1} = rule1;
    L{end+1} = '';
    L{end+1} = ' DEPLOYMENT CONTEXT';
    L{end+1} = sprintf('   Terrain type     : %s  (Nakagami m = %.2f)', P.terrain, P.m);
    L{end+1} = sprintf('   Season           : %s  (alpha = %.1f, beta = %.1f)', P.season, P.alpha, P.beta);
    L{end+1} = fog_line;
    L{end+1} = '';
    L{end+1} = ' SYSTEM CONFIGURATION';
    L{end+1} = sprintf('   RIS elements     : N = %d', P.N);
    L{end+1} = '   Relay protocol   : Decode-and-Forward (DF)';
    L{end+1} = '   Combining scheme : Selection Combining (SC), RF and FSO on hop 2';
    L{end+1} = '   Modulation       : BPSK';
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = sprintf(' REQUIRED AVERAGE SNR, OUTAGE TARGET  (P_out <= %.0e, threshold %.1f dB)', ...
                       P.tgt_out, 10*log10(P.gamma_th));
    L{end+1} = rule2;
    L{end+1} = sprintf('   RIS-Hybrid N=%-3d : %s', P.N, fmt_req(q.out_ris, q.out_ris_st, P));
    L{end+1} = sprintf('   Hybrid (no RIS)  : %s', fmt_req(q.out_no, q.out_no_st, P));
    L{end+1} = sprintf('   RF only          : %s', fmt_req(q.out_rf, q.out_rf_st, P));
    L{end+1} = sprintf('   RIS SNR saving   : %s', fmt_saving(q.save_out, q.save_out_kind));
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = sprintf(' REQUIRED AVERAGE SNR, BER TARGET  (BER <= %.0e, BPSK)', P.tgt_ber);
    L{end+1} = rule2;
    L{end+1} = sprintf('   RIS-Hybrid N=%-3d : %s', P.N, fmt_req(q.ber_ris, q.ber_ris_st, P));
    L{end+1} = sprintf('   Hybrid (no RIS)  : %s', fmt_req(q.ber_no, q.ber_no_st, P));
    L{end+1} = sprintf('   RF only          : %s', fmt_req(q.ber_rf, q.ber_rf_st, P));
    L{end+1} = sprintf('   RIS SNR saving   : %s', fmt_saving(q.save_ber, q.save_ber_kind));
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = sprintf(' RIS-ASSISTED SYSTEM AT AVERAGE SNR = %d dB', round(R.mid.snr_dB));
    L{end+1} = rule2;
    L{end+1} = sprintf('   Outage prob      : %.4e', R.mid.out);
    L{end+1} = sprintf('   Ergodic capacity : %.4f bits/s/Hz', R.mid.cap);
    L{end+1} = sprintf('   BER (BPSK)       : %.4e', R.mid.ber);
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = ' LINK BUDGET: AVERAGE SNR -> TRANSMIT POWER  (RF, per hop)';
    L{end+1} = rule2;
    L{end+1} = '   P_tx = SNR + margin + path loss - antenna gains + noise floor';
    L{end+1} = sprintf('   Path loss        : %6.1f dB   (free space, %.2f GHz, %.2f km)', LB.L_path_dB, P.f_GHz, P.d_km);
    L{end+1} = sprintf('   Antenna gains    : %6.1f dBi  (transmit + receive)', P.G_dBi);
    L{end+1} = sprintf('   Noise floor      : %6.1f dBm  (kTB over %.2f MHz + NF %.1f dB)', LB.noise_dBm, P.B_MHz, P.NF_dB);
    L{end+1} = sprintf('   Impl. margin     : %6.1f dB', P.margin_dB);
    L{end+1} = sprintf('   RIS excess loss  : %6.1f dB   (0 = normalised model)', P.L_ris_dB);
    L{end+1} = sprintf('   Power budget     : %6.1f dBm  -> average SNR available %.1f dB', P.tx_max_dBm, LB.snr_at_pmax);
    L{end+1} = '';
    b1 = budget_lines(q.gov_ris, q.gov_ris_by, LB.ptx_ris, LB.margin_ris);
    b2 = budget_lines(q.gov_no,  q.gov_no_by,  LB.ptx_no,  LB.margin_no);
    L{end+1} = sprintf('   RIS-Hybrid N=%-3d : %s', P.N, b1{1});
    if numel(b1) > 1, L{end+1} = ['                      ', b1{2}]; end
    L{end+1} = sprintf('   Hybrid (no RIS)  : %s', b2{1});
    if numel(b2) > 1, L{end+1} = ['                      ', b2{2}]; end
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = sprintf(' AMPLIFIER POWER  (PA efficiency %.0f%%, solar output %.0f W)', P.pa_eff, P.solar_w);
    L{end+1} = rule2;
    L{end+1} = sprintf('   RIS-Hybrid N=%-3d : %s', P.N, power_line(LB.ok_ris, LB.ptx_ris, PW.ptx_ris_W, PW.pdc_ris_W));
    L{end+1} = sprintf('   Hybrid (no RIS)  : %s', power_line(LB.ok_no, LB.ptx_no, PW.ptx_no_W, PW.pdc_no_W));
    if isfinite(PW.saved_W)
        L{end+1} = sprintf('   DC power saved   : %s  (%.2f%% of solar output)', fmt_watts(PW.saved_W), PW.saved_pct);
    elseif LB.ok_ris
        L{end+1} = '   DC power saved   : n/a  (only the RIS-assisted link closes within the budget)';
    else
        L{end+1} = '   DC power saved   : n/a  (the RIS-assisted link does not close within the budget)';
    end
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = ' ARRAY SIZE  (outage-target SNR against N)';
    L{end+1} = rule2;
    row = '   ';
    for k = 1:numel(NR.grid)
        if isfinite(NR.req(k))
            row = [row, sprintf('N=%d: %.1f  ', NR.grid(k), NR.req(k))]; %#ok<AGROW>
        else
            row = [row, sprintf('N=%d: >%g  ', NR.grid(k), P.SNR_max)]; %#ok<AGROW>
        end
        if k == 5
            L{end+1} = row; %#ok<AGROW>
            row = '   ';
        end
    end
    L{end+1} = row;
    if isfinite(NR.N)
        L{end+1} = sprintf('   Recommended N    : %d  (smallest N within %.1f dB of N = 100; selected N = %d)', ...
                           NR.N, NR.tol_dB, P.N);
        if NR.N < 20
            L{end+1} = '   Note: figures for N below 20 rely on the central-limit model outside';
            L{end+1} = '   its validated range; treat them as indicative.';
        end
    else
        L{end+1} = '   Recommended N    : n/a  (outage target not met for N up to 100 in the sweep)';
    end
    L{end+1} = '';
    L{end+1} = rule2;
    L{end+1} = ' VALIDITY NOTES';
    L{end+1} = rule2;
    for k = 1:numel(R.notes)
        w = wrap_text(R.notes{k}, 62);
        L{end+1} = ['   * ', w{1}]; %#ok<AGROW>
        for j = 2:numel(w)
            L{end+1} = ['     ', w{j}]; %#ok<AGROW>
        end
    end
    L{end+1} = rule1;
    lines = L(:);
end

function c = budget_lines(gov, by, ptx, margin)
    if ~isfinite(gov)
        c = {'target not met in the sweep - no power figure'};
    else
        c = {sprintf('needs %.1f dB (%s) -> P_tx = %.1f dBm', gov, by, ptx), ''};
        if margin >= 0
            c{2} = sprintf('margin %+.1f dB against the budget : link CLOSES', margin);
        else
            c{2} = sprintf('margin %+.1f dB against the budget : link DOES NOT CLOSE', margin);
        end
    end
end

function s = power_line(ok, ptx_dBm, ptx_W, pdc_W)
    if ~isfinite(ptx_dBm)
        s = 'n/a';
    elseif ok
        s = sprintf('radiates %s, amplifier draws %s', fmt_watts(ptx_W), fmt_watts(pdc_W));
    else
        s = sprintf('would need %s radiated - exceeds the budget', fmt_watts(ptx_W));
    end
end

function s = fmt_watts(w)
    if abs(w) >= 1
        s = sprintf('%.2f W', w);
    elseif abs(w) >= 1e-3
        s = sprintf('%.1f mW', w*1e3);
    else
        s = sprintf('%.3g mW', w*1e3);
    end
end

function out = wrap_text(str, width)
    words = strsplit(str, ' ');
    out = {};  cur = '';
    for k = 1:numel(words)
        if isempty(cur)
            cur = words{k};
        elseif numel(cur) + 1 + numel(words{k}) <= width
            cur = [cur, ' ', words{k}]; %#ok<AGROW>
        else
            out{end+1} = cur; %#ok<AGROW>
            cur = words{k};
        end
    end
    out{end+1} = cur;
end

function s = status_line(R)
    q = R.req;  P = R.P;
    s = sprintf('  Done in %.2f s.  Required SNR: %s (outage) | %s (BER).  ', ...
                R.elapsed_s, fmt_req(q.out_ris, q.out_ris_st, P), fmt_req(q.ber_ris, q.ber_ris_st, P));
    if ~isfinite(R.lb.ptx_ris)
        s = [s, 'Target not met in sweep.'];
    elseif R.lb.ok_ris
        s = [s, sprintf('TX power %.1f dBm, link closes with %.1f dB margin.', R.lb.ptx_ris, R.lb.margin_ris)];
    else
        s = [s, sprintf('TX power %.1f dBm exceeds the %.0f dBm budget.', R.lb.ptx_ris, P.tx_max_dBm)];
    end
end

function write_report(filename, R)
    fid = fopen(filename, 'w');
    if fid < 0
        error('RIS_Planning_Tool:file', 'Cannot open %s for writing.', filename);
    end
    fprintf(fid, '%s\n', repmat('=', 1, 68));
    fprintf(fid, 'RIS-ASSISTED HYBRID RF/FSO PLANNING TOOL  v%s\n', R.version);
    fprintf(fid, 'HIT Electronic Engineering - Master of Technology Research\n');
    fprintf(fid, 'Report generated: %s\n', datestr(now));
    fprintf(fid, '%s\n\n', repmat('=', 1, 68));
    S = build_summary(R);
    for k = 1:numel(S)
        fprintf(fid, '%s\n', S{k});
    end
    fprintf(fid, '\n%s\n', repmat('-', 1, 118));
    fprintf(fid, 'NUMERICAL RESULTS  (RIS = RIS-assisted hybrid, HYB = hybrid without RIS, RF = RF only)\n');
    fprintf(fid, '%s\n', repmat('-', 1, 118));
    fprintf(fid, '%-8s %-12s %-12s %-12s %-9s %-9s %-9s %-12s %-12s %-12s\n', ...
        'SNR(dB)', 'Pout RIS', 'Pout HYB', 'Pout RF', 'Cap RIS', 'Cap HYB', 'Cap RF', 'BER RIS', 'BER HYB', 'BER RF');
    for k = 1:numel(R.SNR_dB)
        fprintf(fid, '%-8.1f %-12.4e %-12.4e %-12.4e %-9.4f %-9.4f %-9.4f %-12.4e %-12.4e %-12.4e\n', ...
            R.SNR_dB(k), R.Pout_RIS(k), R.Pout_noRIS(k), R.Pout_RF(k), ...
            R.Cap_RIS(k), R.Cap_noRIS(k), R.Cap_RF(k), ...
            R.BER_RIS(k), R.BER_noRIS(k), R.BER_RF(k));
    end
    fclose(fid);
end

% =========================================================================
%  SELF-TEST, MONTE CARLO VALIDATION, BENCHMARK
% =========================================================================

function ok = run_selftest()
    % Checks the engine against independent calculations and against the
    % outage/capacity values produced by v1.0. Takes a few seconds.
    fprintf('RIS_Planning_Tool v%s self-test\n', tool_version());
    n_fail = 0;

    % 1. Gamma-Gamma table against direct adaptive quadrature of the PDF
    pairs = [11.6 10.1; 4.0 1.9; 4.2 1.4];
    worst = 0;  worst_norm = 0;
    for k = 1:size(pairs, 1)
        T = gg_cdf_table(pairs(k,1), pairs(k,2));
        worst_norm = max(worst_norm, abs(T.norm - 1));
        for I = [0.01 0.1 0.5 1 3]
            ref = integral(@(t) gg_pdf_logI(t, pairs(k,1), pairs(k,2)), log(1e-12), log(I), ...
                           'RelTol', 1e-10, 'AbsTol', 1e-300);
            worst = max(worst, abs(gg_cdf_eval(T, I) / ref - 1));
        end
    end
    n_fail = n_fail + report_check('Gamma-Gamma CDF table vs direct quadrature', worst, 1e-5);
    n_fail = n_fail + report_check('Gamma-Gamma CDF normalisation', worst_norm, 1e-8);

    % 2. CDF-form BER integral against the closed MGF form (RF only)
    worst = 0;
    for m = [0.5 1 1.5 3]
        for s_dB = [0 10 20]
            g  = 10^(s_dB/10);
            b1 = integral(@(u) exp(-u.^2) .* cdf_nak(u.^2 ./ g, m), 0, 6.5, 'RelTol', 1e-8, 'AbsTol', 1e-20) / sqrt(pi);
            worst = max(worst, abs(b1 / ber_rf(g, m) - 1));
        end
    end
    n_fail = n_fail + report_check('BER integral (CDF form) vs closed form, Nakagami-m', worst, 1e-5);

    % 3. Regression against v1.0 outage and capacity (Highveld, dry, N = 50)
    P = default_params();  P.alpha = 11.6;  P.beta = 10.1;  P.season = 'Dry Season';
    R = ris_compute(P);
    ref_out = [3.4742e-01 4.9093e-04 1.2532e-08];      % at 0, 10, 20 dB
    ref_cap = [0.6294 1.8995 3.5006];
    idx = [11 21 31];
    n_fail = n_fail + report_check('Outage reproduces v1.0 (Highveld, dry, N=50)', max(abs(R.Pout_RIS(idx) ./ ref_out - 1)), 2e-3);
    n_fail = n_fail + report_check('Capacity reproduces v1.0 (Highveld, dry, N=50)', max(abs(R.Cap_RIS(idx) ./ ref_cap - 1)), 2e-3);

    % 4. BER reference values (default configuration; Octave 8.4, v1.2.0)
    R = ris_compute(default_params());
    n_fail = n_fail + report_check('BER, RIS hybrid at 12 dB = 1.2028e-03', abs(R.BER_RIS(23) / 1.2028e-03 - 1), 5e-3);
    n_fail = n_fail + report_check('BER, hybrid without RIS at 18 dB = 8.2352e-04', abs(R.BER_noRIS(29) / 8.2352e-04 - 1), 5e-3);

    % 5. Sanity of the curves
    mono = all(diff(R.BER_RIS) <= 0) && all(diff(R.Pout_RIS) <= 0) && all(diff(R.Cap_RIS) >= 0);
    n_fail = n_fail + report_check('BER and outage fall, capacity rises with SNR', double(~mono), 0.5);
    bounded = all(R.BER_RIS > 0 & R.BER_RIS <= 0.5) && all(R.BER_noRIS > 0 & R.BER_noRIS <= 0.5);
    n_fail = n_fail + report_check('BER lies in (0, 0.5]', double(~bounded), 0.5);

    % 6. Unmet target is reported as not met
    [v, st] = find_req(0:5, 0.5*ones(1, 6), 1e-3);
    n_fail = n_fail + report_check('Unmet target returns NaN / status -1', double(~(isnan(v) && st == -1)), 0.5);

    % 7. Link-budget arithmetic (2.4 GHz, 5 km, 20 MHz, NF 7 dB, 20 dBi)
    exp_off = (92.45 + 20*log10(2.4) + 20*log10(5)) - 20 + (-174 + 10*log10(20e6) + 7);
    n_fail = n_fail + report_check('Link-budget offset', abs(R.lb.offset_dB - exp_off), 1e-9);

    ok = (n_fail == 0);
    if ok
        fprintf('ALL CHECKS PASSED\n');
    else
        fprintf('%d CHECK(S) FAILED\n', n_fail);
    end
end

function failed = report_check(name, err, tol)
    failed = ~(err <= tol);
    if failed, tag = 'FAIL'; else, tag = 'pass'; end
    fprintf('  [%s] %-55s  error %.2e (tolerance %.0e)\n', tag, name, err, tol);
end

function V = run_validation(varargin)
    % Monte Carlo simulation of the same channel model, compared with the
    % analytical curves. The RIS hop is simulated exactly (sum of N products
    % of Nakagami-m amplitudes), so this also measures the error of the
    % central-limit approximation.
    P = default_params();
    n_total = 1e6;
    if nargin >= 1 && isstruct(varargin{1}), P = fill_defaults(varargin{1}); end
    if nargin >= 2 && ~isempty(varargin{2}), n_total = varargin{2}; end

    R   = ris_compute(P);
    snr = 10.^(R.SNR_dB/10);
    nP  = numel(snr);
    k_fso = 10^(-R.fog.electrical_dB/10);
    k_ris = 10^(-P.L_ris_dB/10);

    old_state = [];
    if exist('rng', 'file') == 2 || exist('rng', 'builtin') == 5
        old_state = rng;
        rng(20261111);
    end

    chunk = max(1000, min(40000, floor(2e6 / P.N)));
    cnt = zeros(2, nP);  sb = zeros(2, nP);  sb2 = zeros(2, nP);
    sc  = zeros(2, nP);  sc2 = zeros(2, nP);
    done = 0;
    while done < n_total
        n  = min(chunk, n_total - done);
        A1 = sqrt(rand_gamma(P.m, [n, P.N]) / P.m);
        A2 = sqrt(rand_gamma(P.m, [n, P.N]) / P.m);
        Z  = sum(A1 .* A2, 2);
        x1_ris = k_ris * Z.^2;                         % hop 1 with RIS
        x1_dir = rand_gamma(P.m, [n, 1]) / P.m;        % hop 1 direct
        x_rf   = rand_gamma(P.m, [n, 1]) / P.m;        % hop 2 RF
        Iw     = (rand_gamma(P.alpha, [n, 1]) / P.alpha) .* (rand_gamma(P.beta, [n, 1]) / P.beta);
        x2     = max(x_rf, k_fso * Iw.^2);             % hop 2 selection combining
        X      = [min(x1_ris, x2), min(x1_dir, x2)];
        for c = 1:2
            G  = X(:, c) * snr;                        % n x nP
            qb = 0.5 * erfc(sqrt(G));
            cb = 0.5 * log2(1 + G);
            cnt(c, :) = cnt(c, :) + sum(G < P.gamma_th, 1);
            sb(c, :)  = sb(c, :)  + sum(qb, 1);
            sb2(c, :) = sb2(c, :) + sum(qb.^2, 1);
            sc(c, :)  = sc(c, :)  + sum(cb, 1);
            sc2(c, :) = sc2(c, :) + sum(cb.^2, 1);
        end
        done = done + n;
    end
    if ~isempty(old_state), rng(old_state); end

    V.P = P;  V.n = n_total;  V.SNR_dB = R.SNR_dB;
    V.out_mc = cnt / n_total;
    V.ber_mc = sb / n_total;
    V.cap_mc = sc / n_total;
    V.out_an = [R.Pout_RIS; R.Pout_noRIS];
    V.ber_an = [R.BER_RIS;  R.BER_noRIS];
    V.cap_an = [R.Cap_RIS;  R.Cap_noRIS];
    % Standard errors of the simulation
    V.out_se = sqrt(max(V.out_mc .* (1 - V.out_mc), 0) / n_total);
    V.ber_se = sqrt(max(sb2 / n_total - V.ber_mc.^2, 0) / n_total);
    V.cap_se = sqrt(max(sc2 / n_total - V.cap_mc.^2, 0) / n_total);
    % A point is "resolved" when the simulation itself is good to 2%
    V.out_resolved = V.out_se <= 0.02 * V.out_mc & cnt >= 100 & (n_total - cnt) >= 100;
    V.ber_resolved = V.ber_se <= 0.02 * V.ber_mc & V.ber_mc > 0;
    V.out_dev = abs(V.out_an ./ V.out_mc - 1);
    V.ber_dev = abs(V.ber_an ./ V.ber_mc - 1);
    V.cap_dev = abs(V.cap_an ./ V.cap_mc - 1);
    % Model and simulation disagree when they differ by more than 4 standard errors
    V.out_sig = V.out_resolved & abs(V.out_an - V.out_mc) > 4 * V.out_se;
    V.ber_sig = V.ber_resolved & abs(V.ber_an - V.ber_mc) > 4 * V.ber_se;

    names = {'RIS-assisted hybrid', 'Hybrid without RIS'};
    fprintf('\nMonte Carlo validation, v%s: %s, %s, m = %.2f, alpha = %.1f, beta = %.1f, N = %d, %g samples\n', ...
            tool_version(), P.terrain, P.season, P.m, P.alpha, P.beta, P.N, n_total);
    for c = 1:2
        fprintf('\n  %s\n', names{c});
        fprintf('  %6s  %11s %11s %7s   %11s %11s %7s   %8s %8s %6s\n', ...
                'SNR dB', 'Pout model', 'Pout MC', 'dev %', 'BER model', 'BER MC', 'dev %', 'C model', 'C MC', 'dev %');
        for i = 1:2:nP
            fprintf('  %6.0f  %11.4e %11.4e %7s   %11.4e %11.4e %7s   %8.4f %8.4f %6.2f\n', ...
                R.SNR_dB(i), V.out_an(c, i), V.out_mc(c, i), dev_str(V.out_dev(c, i), V.out_resolved(c, i), V.out_sig(c, i)), ...
                V.ber_an(c, i), V.ber_mc(c, i), dev_str(V.ber_dev(c, i), V.ber_resolved(c, i), V.ber_sig(c, i)), ...
                V.cap_an(c, i), V.cap_mc(c, i), 100 * V.cap_dev(c, i));
        end
        V.max_out_dev(c) = max([0, V.out_dev(c, V.out_resolved(c, :))]);
        V.max_ber_dev(c) = max([0, V.ber_dev(c, V.ber_resolved(c, :))]);
        V.max_cap_dev(c) = max(V.cap_dev(c, :));
        V.n_sig(c)       = sum(V.out_sig(c, :)) + sum(V.ber_sig(c, :));
        lo_out = last_resolved(R.SNR_dB, V.out_resolved(c, :));
        lo_ber = last_resolved(R.SNR_dB, V.ber_resolved(c, :));
        fprintf('  Largest deviation over resolved points: outage %.2f%% (resolved up to %g dB), BER %.2f%% (up to %g dB), capacity %.2f%%\n', ...
                100 * V.max_out_dev(c), lo_out, 100 * V.max_ber_dev(c), lo_ber, 100 * V.max_cap_dev(c));
        fprintf('  Resolved points where model and simulation differ by more than 4 standard errors: %d\n', V.n_sig(c));
    end
    fprintf('\n  "-" : the simulation is not accurate to 2%% at this point with %g samples (every second SNR point is listed).\n', n_total);
    fprintf('  "*" : model and simulation differ by more than 4 standard errors.\n\n');
end

function v = last_resolved(SNR_dB, mask)
    k = find(mask, 1, 'last');
    if isempty(k), v = NaN; else, v = SNR_dB(k); end
end

function s = dev_str(dev, resolved, sig)
    if ~resolved
        s = '-';
    elseif sig
        s = sprintf('%.2f*', 100 * dev);
    else
        s = sprintf('%.2f', 100 * dev);
    end
end

function G = rand_gamma(a, sz)
    % Gamma(shape a, scale 1) random numbers without toolboxes
    % (Marsaglia and Tsang, ACM Trans. Math. Softw. 26, 2000).
    n = prod(sz);
    a_in = a;
    if a < 1, a = a + 1; end
    d = a - 1/3;
    c = 1 / sqrt(9*d);
    G = zeros(n, 1);
    todo = (1:n).';
    while ~isempty(todo)
        k = numel(todo);
        x = randn(k, 1);
        v = (1 + c*x).^3;
        u = rand(k, 1);
        acc = (v > 0) & (log(u) < 0.5*x.^2 + d - d*v + d*log(max(v, realmin)));
        G(todo(acc)) = d * v(acc);
        todo = todo(~acc);
    end
    if a_in < 1
        G = G .* rand(n, 1).^(1/a_in);
    end
    G = reshape(G, sz);
end

function B = run_benchmark()
    % Wall-clock time of one complete analysis against problem size.
    reps = 5;
    fprintf('\nRIS_Planning_Tool v%s benchmark (mean of %d runs, seconds)\n', tool_version(), reps);
    P0 = default_params();
    ris_compute(P0);                       % warm-up

    fprintf('\n  SNR points in the sweep (N = 50, moderate turbulence)\n');
    ranges = [0 10; -10 10; -10 30; -20 40; -20 50];
    B.points = zeros(size(ranges, 1), 2);
    for k = 1:size(ranges, 1)
        P = P0;  P.SNR_min = ranges(k, 1);  P.SNR_max = ranges(k, 2);
        B.points(k, :) = [ranges(k, 2) - ranges(k, 1) + 1, time_runs(P, reps)];
        fprintf('    %3d points : %.3f s\n', B.points(k, 1), B.points(k, 2));
    end

    fprintf('\n  RIS elements (41 points, moderate turbulence)\n');
    Ns = [1 20 50 100];
    B.elements = zeros(numel(Ns), 2);
    for k = 1:numel(Ns)
        P = P0;  P.N = Ns(k);
        B.elements(k, :) = [Ns(k), time_runs(P, reps)];
        fprintf('    N = %3d    : %.3f s\n', Ns(k), B.elements(k, 2));
    end

    fprintf('\n  Turbulence regime (41 points, N = 50)\n');
    S = season_table();
    B.regime = zeros(numel(S), 1);
    for k = 1:numel(S)
        P = P0;  P.alpha = S(k).alpha;  P.beta = S(k).beta;
        B.regime(k) = time_runs(P, reps);
        fprintf('    %-18s: %.3f s\n', S(k).name, B.regime(k));
    end
    fprintf('\n');
end

function t = time_runs(P, reps)
    acc = 0;
    for r = 1:reps
        t0 = tic;
        ris_compute(P);
        acc = acc + toc(t0);
    end
    t = acc / reps;
end

% =========================================================================
%  GRAPHICAL INTERFACE
% =========================================================================

function launch_gui()
    C = tool_colors();

    %% ── Create main figure ───────────────────────────────────────────────
    fig = uifigure('Name', ...
        sprintf('RIS-Assisted Hybrid RF/FSO Planning Tool v%s — Zimbabwe Rural Connectivity', tool_version()), ...
        'Position', [44 41 1144 640], ...
        'Color', [0.96 0.96 0.96], ...
        'Resize', 'on');

    %% ── TITLE BANNER ─────────────────────────────────────────────────────
    titlePanel = uipanel(fig, ...
        'Position', [9 599 1126 34], ...
        'BackgroundColor', C.DARKBLUE, ...
        'BorderType', 'none');
    uilabel(titlePanel, ...
        'Text', 'RIS-ASSISTED HYBRID RF/FSO COMMUNICATION SYSTEM — RURAL ZIMBABWE DEPLOYMENT PLANNING TOOL', ...
        'Position', [9 7 1109 20], ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', C.WHITE, ...
        'HorizontalAlignment', 'center');

    %% ── LEFT PANEL: INPUTS (two tabs) ────────────────────────────────────
    leftPanel = uipanel(fig, ...
        'Title', 'SYSTEM PARAMETERS', ...
        'Position', [9 8 273 586], ...
        'BackgroundColor', C.LIGHTGREY, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', C.DARKBLUE);

    inTabs = uitabgroup(leftPanel, 'Position', [4 68 265 492]);
    tabA   = uitab(inTabs, 'Title', 'Site / channel');
    tabB   = uitab(inTabs, 'Title', 'Link budget');

    TT = terrain_table();
    ST = season_table();

    % ── Tab A: terrain ───────────────────────────────────────────────────
    uilabel(tabA, 'Text', 'Zimbabwe Terrain Type', ...
        'Position', [8 438 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    terrainDrop = uidropdown(tabA, ...
        'Items', [{TT.label}, {'Custom — enter m below'}], ...
        'Position', [8 414 246 22], ...
        'FontSize', 9, ...
        'BackgroundColor', C.WHITE, ...
        'ValueChangedFcn', @(src, evt) on_terrain_changed(fig));
    uilabel(tabA, 'Text', 'Custom m:', ...
        'Position', [8 390 70 18], 'FontSize', 9);
    m_field = uieditfield(tabA, 'numeric', ...
        'Value', 1.5, 'Limits', [0.5 10], ...
        'Position', [80 390 60 18], 'FontSize', 9, 'Enable', 'off');
    uilabel(tabA, 'Text', '(0.5 to 10)', ...
        'Position', [148 390 100 18], 'FontSize', 9, 'FontColor', C.DARKGREY);

    % ── Tab A: season ────────────────────────────────────────────────────
    uilabel(tabA, 'Text', 'Season / Atmospheric Condition', ...
        'Position', [8 364 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    seasonDrop = uidropdown(tabA, ...
        'Items', [{ST.label}, {'Custom — enter α, β below'}], ...
        'Position', [8 340 246 22], ...
        'FontSize', 9, ...
        'BackgroundColor', C.WHITE, ...
        'ValueChangedFcn', @(src, evt) on_season_changed(fig));
    seasonDrop.Value = ST(2).label;          % moderate-turbulence baseline
    uilabel(tabA, 'Text', 'Custom α:', ...
        'Position', [8 316 62 18], 'FontSize', 9);
    alpha_field = uieditfield(tabA, 'numeric', ...
        'Value', 4.0, 'Limits', [1 30], ...
        'Position', [72 316 50 18], 'FontSize', 9, 'Enable', 'off');
    uilabel(tabA, 'Text', 'β:', ...
        'Position', [136 316 18 18], 'FontSize', 9);
    beta_field = uieditfield(tabA, 'numeric', ...
        'Value', 1.9, 'Limits', [1 30], ...
        'Position', [156 316 50 18], 'FontSize', 9, 'Enable', 'off');

    % ── Tab A: fog / visibility margin (FSO branch only) ─────────────────
    fogCheck = uicheckbox(tabA, ...
        'Text', 'Add fog/visibility margin (FSO only)', ...
        'Value', false, ...
        'Position', [8 292 245 16], ...
        'FontSize', 9, 'FontColor', C.DARKGREY, ...
        'ValueChangedFcn', @(src, evt) on_fog_changed(fig));
    uilabel(tabA, 'Text', 'Visibility (km):', ...
        'Position', [8 270 88 18], 'FontSize', 9);
    visibility_field = uieditfield(tabA, 'numeric', ...
        'Value', 2, 'Limits', [0.05 50], ...
        'Position', [100 270 60 18], 'FontSize', 9, 'Enable', 'off');

    uipanel(tabA, 'Position', [8 260 246 2], ...
        'BackgroundColor', C.BLUE, 'BorderType', 'none');

    % ── Tab A: RIS elements ──────────────────────────────────────────────
    uilabel(tabA, 'Text', 'Number of RIS Elements (N)', ...
        'Position', [8 238 190 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    N_label = uilabel(tabA, 'Text', 'N = 50', ...
        'Position', [200 238 54 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.BLUE, ...
        'HorizontalAlignment', 'right');
    N_slider = uislider(tabA, ...
        'Limits', [1 100], 'Value', 50, ...
        'MajorTicks', [1 10 20 50 100], ...
        'Position', [12 222 236 3], ...
        'ValueChangedFcn', @(s, e) set(N_label, 'Text', sprintf('N = %d', round(s.Value))));

    % ── Tab A: SNR sweep ─────────────────────────────────────────────────
    uilabel(tabA, 'Text', 'SNR Sweep (dB)', ...
        'Position', [8 170 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    uilabel(tabA, 'Text', 'Min:', 'Position', [8 146 34 18], 'FontSize', 9);
    SNR_min_field = uieditfield(tabA, 'numeric', ...
        'Value', -10, 'Limits', [-20 0], ...
        'Position', [44 146 60 18], 'FontSize', 9);
    uilabel(tabA, 'Text', 'Max:', 'Position', [124 146 34 18], 'FontSize', 9);
    SNR_max_field = uieditfield(tabA, 'numeric', ...
        'Value', 30, 'Limits', [10 50], ...
        'Position', [160 146 60 18], 'FontSize', 9);

    % ── Tab A: outage threshold ──────────────────────────────────────────
    uilabel(tabA, 'Text', 'SNR Threshold γth (linear)', ...
        'Position', [8 120 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    gamma_th_field = uieditfield(tabA, 'numeric', ...
        'Value', 1, 'Limits', [0.1 10], ...
        'Position', [8 96 60 18], 'FontSize', 9);
    uilabel(tabA, 'Text', '(1 = 0 dB threshold)', ...
        'Position', [76 96 170 18], 'FontSize', 9, 'FontColor', C.DARKGREY);

    % ── Tab A: performance targets ───────────────────────────────────────
    uilabel(tabA, 'Text', 'Performance Targets', ...
        'Position', [8 70 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    uilabel(tabA, 'Text', 'Outage:', 'Position', [8 46 50 18], 'FontSize', 9);
    target_out_field = uieditfield(tabA, 'numeric', ...
        'Value', 1e-3, 'Limits', [1e-6 0.5], ...
        'Position', [58 46 62 18], 'FontSize', 9);
    uilabel(tabA, 'Text', 'BER:', 'Position', [134 46 34 18], 'FontSize', 9);
    target_ber_field = uieditfield(tabA, 'numeric', ...
        'Value', 1e-3, 'Limits', [1e-6 0.4], ...
        'Position', [168 46 62 18], 'FontSize', 9);

    % ── Tab B: RF link budget ────────────────────────────────────────────
    uilabel(tabB, 'Text', 'RF Link Budget (per hop)', ...
        'Position', [8 438 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    f_field      = budget_row(tabB, 412, 'Carrier frequency (GHz):',    2.4, [0.1 100]);
    d_field      = budget_row(tabB, 386, 'Hop distance (km):',          5,   [0.05 100]);
    B_field      = budget_row(tabB, 360, 'Bandwidth (MHz):',            20,  [0.01 2000]);
    NF_field     = budget_row(tabB, 334, 'Noise figure (dB):',          7,   [0 30]);
    G_field      = budget_row(tabB, 308, 'Antenna gains Tx+Rx (dBi):',  20,  [-20 100]);
    margin_field = budget_row(tabB, 282, 'Implementation margin (dB):', 0,   [0 40]);
    Lris_field   = budget_row(tabB, 256, 'RIS path excess loss (dB):',  0,   [0 120]);

    uipanel(tabB, 'Position', [8 244 246 2], ...
        'BackgroundColor', C.BLUE, 'BorderType', 'none');

    % ── Tab B: power ─────────────────────────────────────────────────────
    uilabel(tabB, 'Text', 'Power', ...
        'Position', [8 220 245 16], ...
        'FontWeight', 'bold', 'FontSize', 10, 'FontColor', C.DARKGREY);
    tx_power_field = budget_row(tabB, 194, 'Max Transmit Power (dBm):', 20, [0 50]);
    pa_field       = budget_row(tabB, 168, 'PA efficiency (%):',        25, [1 100]);
    solar_field    = budget_row(tabB, 142, 'Solar Panel Output (W):',   50, [5 500]);

    uipanel(tabB, 'Position', [8 130 246 2], ...
        'BackgroundColor', C.BLUE, 'BorderType', 'none');

    uilabel(tabB, ...
        'Text', {'Average SNR per link (dB) =', ...
                 '   Ptx + G - L - Noise - margin', ...
                 'L = 92.45 + 20log10(f) + 20log10(d)', ...
                 'Noise = -174 + 10log10(B) + NF', ...
                 'Margin and RIS excess loss of 0 dB', ...
                 'give the normalised best-case model.'}, ...
        'Position', [8 30 246 94], ...
        'FontSize', 8, 'FontColor', C.DARKGREY, ...
        'VerticalAlignment', 'top');

    %% ── COMPUTE and EXPORT buttons (below the tabs) ──────────────────────
    uibutton(leftPanel, ...
        'Text', '▶  COMPUTE RESULTS', ...
        'Position', [9 36 255 28], ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'BackgroundColor', C.GREEN, ...
        'FontColor', C.WHITE, ...
        'ButtonPushedFcn', @(src, evt) on_compute(fig));
    uibutton(leftPanel, ...
        'Text', '📄  EXPORT REPORT', ...
        'Position', [9 6 255 26], ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'BackgroundColor', C.ORANGE, ...
        'FontColor', C.WHITE, ...
        'ButtonPushedFcn', @(src, evt) on_export(fig));

    %% ── MIDDLE PANEL: PLOTS ──────────────────────────────────────────────
    plotPanel = uipanel(fig, ...
        'Title', 'PERFORMANCE CURVES', ...
        'Position', [290 320 598 275], ...
        'BackgroundColor', C.WHITE, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', C.DARKBLUE);

    tabGroup = uitabgroup(plotPanel, 'Position', [4 4 590 254]);
    tab1 = uitab(tabGroup, 'Title', 'Outage Probability');
    tab2 = uitab(tabGroup, 'Title', 'Ergodic Capacity');
    tab3 = uitab(tabGroup, 'Title', 'Bit Error Rate');

    ax1 = uiaxes(tab1, 'Position', [9 4 568 221]);
    ax2 = uiaxes(tab2, 'Position', [9 4 568 221]);
    ax3 = uiaxes(tab3, 'Position', [9 4 568 221]);

    for ax = [ax1 ax2 ax3]
        ax.FontSize    = 10;
        ax.GridColor   = [0.8 0.8 0.8];
        ax.GridAlpha   = 0.5;
        ax.Box         = 'on';
        grid(ax, 'on');
    end

    %% ── BOTTOM MIDDLE: LINK BUDGET ───────────────────────────────────────
    budgetPanel = uipanel(fig, ...
        'Title', 'LINK BUDGET SUMMARY', ...
        'Position', [290 8 598 305], ...
        'BackgroundColor', C.WHITE, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', C.DARKBLUE);

    budgetText = uitextarea(budgetPanel, ...
        'Position', [9 8 581 279], ...
        'FontSize', 10, 'FontName', 'Courier New', ...
        'Editable', 'off', ...
        'BackgroundColor', [0.97 0.97 1.00], ...
        'Value', {'Click COMPUTE to generate link budget summary...'});

    %% ── RIGHT PANEL: RESULTS ─────────────────────────────────────────────
    rightPanel = uipanel(fig, ...
        'Title', 'KEY RESULTS', ...
        'Position', [898 320 238 275], ...
        'BackgroundColor', C.LIGHTGREY, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', C.DARKBLUE);

    resultLabels = createResultBoxes(rightPanel, C);

    %% ── RIGHT BOTTOM: TERRAIN GUIDE ──────────────────────────────────────
    mapPanel = uipanel(fig, ...
        'Title', 'ZIMBABWE TERRAIN GUIDE', ...
        'Position', [898 8 238 305], ...
        'BackgroundColor', C.LIGHTGREY, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', C.DARKBLUE);

    uitextarea(mapPanel, ...
        'Position', [4 4 227 285], ...
        'FontSize', 9, 'FontName', 'Courier New', ...
        'Editable', 'off', ...
        'BackgroundColor', [0.97 1.00 0.97], ...
        'Value', getTerrainGuide());

    %% ── STATUS BAR ───────────────────────────────────────────────────────
    statusBar = uipanel(fig, ...
        'Position', [9 0 1126 10], ...
        'BackgroundColor', C.DARKBLUE, ...
        'BorderType', 'none');
    statusLabel = uilabel(statusBar, ...
        'Text', '  Ready. Select terrain and season, then click COMPUTE.', ...
        'Position', [4 0 1118 10], ...
        'FontSize', 8, 'FontColor', C.WHITE);

    %% ── Store handles in figure ──────────────────────────────────────────
    handles.terrainDrop      = terrainDrop;
    handles.seasonDrop       = seasonDrop;
    handles.m_field          = m_field;
    handles.alpha_field      = alpha_field;
    handles.beta_field       = beta_field;
    handles.fogCheck         = fogCheck;
    handles.visibility_field = visibility_field;
    handles.N_slider         = N_slider;
    handles.SNR_min_field    = SNR_min_field;
    handles.SNR_max_field    = SNR_max_field;
    handles.gamma_th_field   = gamma_th_field;
    handles.target_out_field = target_out_field;
    handles.target_ber_field = target_ber_field;
    handles.f_field          = f_field;
    handles.d_field          = d_field;
    handles.B_field          = B_field;
    handles.NF_field         = NF_field;
    handles.G_field          = G_field;
    handles.margin_field     = margin_field;
    handles.Lris_field       = Lris_field;
    handles.tx_power_field   = tx_power_field;
    handles.pa_field         = pa_field;
    handles.solar_field      = solar_field;
    handles.ax1 = ax1; handles.ax2 = ax2; handles.ax3 = ax3;
    handles.budgetText       = budgetText;
    handles.statusLabel      = statusLabel;
    handles.resultLabels     = resultLabels;
    handles.lastResults      = [];
    guidata(fig, handles);

    % Run initial computation
    on_compute(fig);
end

function C = tool_colors()
    C.BLUE      = [0.12 0.47 0.71];
    C.DARKBLUE  = [0.08 0.30 0.50];
    C.GREEN     = [0.17 0.63 0.17];
    C.RED       = [0.84 0.15 0.16];
    C.ORANGE    = [1.00 0.50 0.05];
    C.LIGHTGREY = [0.94 0.94 0.94];
    C.WHITE     = [1.00 1.00 1.00];
    C.DARKGREY  = [0.25 0.25 0.25];
end

function fld = budget_row(parent, y, label, value, limits)
    uilabel(parent, 'Text', label, ...
        'Position', [8 y 160 18], 'FontSize', 9);
    fld = uieditfield(parent, 'numeric', ...
        'Value', value, 'Limits', limits, ...
        'Position', [172 y 62 18], 'FontSize', 9);
end

function s = on_off(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

% ── Callbacks ────────────────────────────────────────────────────────────

function on_terrain_changed(fig)
    h = guidata(fig);
    is_custom = strcmp(h.terrainDrop.Value, h.terrainDrop.Items{end});
    set(h.m_field, 'Enable', on_off(is_custom));
    set(h.statusLabel, 'Text', '  Terrain changed. Click COMPUTE to update.');
end

function on_season_changed(fig)
    h = guidata(fig);
    is_custom = strcmp(h.seasonDrop.Value, h.seasonDrop.Items{end});
    set(h.alpha_field, 'Enable', on_off(is_custom));
    set(h.beta_field,  'Enable', on_off(is_custom));
    set(h.statusLabel, 'Text', '  Season changed. Click COMPUTE to update.');
end

function on_fog_changed(fig)
    h = guidata(fig);
    set(h.visibility_field, 'Enable', on_off(h.fogCheck.Value));
    set(h.statusLabel, 'Text', '  Fog margin setting changed. Click COMPUTE to update.');
end

function P = read_params(h)
    P = default_params();

    TT = terrain_table();
    ti = find(strcmp(h.terrainDrop.Items, h.terrainDrop.Value), 1);
    if ti <= numel(TT)
        P.terrain = TT(ti).name;  P.m = TT(ti).m;  P.custom_m = false;
    else
        P.terrain = 'Custom';  P.m = h.m_field.Value;  P.custom_m = true;
    end

    ST = season_table();
    si = find(strcmp(h.seasonDrop.Items, h.seasonDrop.Value), 1);
    if si <= numel(ST)
        P.season = ST(si).name;  P.alpha = ST(si).alpha;  P.beta = ST(si).beta;  P.custom_ab = false;
    else
        P.season = 'Custom';  P.alpha = h.alpha_field.Value;  P.beta = h.beta_field.Value;  P.custom_ab = true;
    end

    P.fog_on        = logical(h.fogCheck.Value);
    P.visibility_km = h.visibility_field.Value;
    P.N             = round(h.N_slider.Value);
    P.SNR_min       = round(h.SNR_min_field.Value);
    P.SNR_max       = round(h.SNR_max_field.Value);
    P.gamma_th      = h.gamma_th_field.Value;
    P.tgt_out       = h.target_out_field.Value;
    P.tgt_ber       = h.target_ber_field.Value;
    P.f_GHz         = h.f_field.Value;
    P.d_km          = h.d_field.Value;
    P.B_MHz         = h.B_field.Value;
    P.NF_dB         = h.NF_field.Value;
    P.G_dBi         = h.G_field.Value;
    P.margin_dB     = h.margin_field.Value;
    P.L_ris_dB      = h.Lris_field.Value;
    P.tx_max_dBm    = h.tx_power_field.Value;
    P.pa_eff        = h.pa_field.Value;
    P.solar_w       = h.solar_field.Value;
end

function on_compute(fig)
    h = guidata(fig);
    set(h.statusLabel, 'Text', '  Computing... please wait.');
    drawnow;

    P = read_params(h);
    try
        R = ris_compute(P);
    catch err
        set(h.statusLabel, 'Text', ['  Computation failed: ', err.message]);
        uialert(fig, err.message, 'Computation failed');
        return;
    end

    draw_plots(h, R);
    update_boxes(h, R);
    set(h.budgetText, 'Value', build_summary(R));

    h.lastResults = R;
    guidata(fig, h);
    set(h.statusLabel, 'Text', status_line(R));
end

function on_export(fig)
    h = guidata(fig);
    if isempty(h.lastResults)
        uialert(fig, 'Please click COMPUTE first.', 'No Results');
        return;
    end

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    filename  = sprintf('RIS_Planning_Report_%s.txt', timestamp);
    [fn, fp]  = uiputfile('*.txt', 'Save Report As', filename);
    if isequal(fn, 0), return; end

    write_report(fullfile(fp, fn), h.lastResults);
    uialert(fig, sprintf('Report saved to:\n%s', fullfile(fp, fn)), ...
        'Export Successful', 'Icon', 'success');
end

% ── Plots and result boxes ───────────────────────────────────────────────

function draw_plots(h, R)
    P = R.P;
    site_snr = R.lb.snr_at_pmax;
    show_site = isfinite(site_snr) && site_snr >= P.SNR_min && site_snr <= P.SNR_max;
    ris_name = sprintf('RIS-Hybrid N=%d', P.N);

    %% ── PLOT 1: Outage ───────────────────────────────────────────────────
    cla(h.ax1);
    semilogy(h.ax1, R.SNR_dB, R.Pout_RF,    'k-',  'LineWidth', 1.5, 'DisplayName', 'RF Only (baseline)');
    hold(h.ax1, 'on');
    semilogy(h.ax1, R.SNR_dB, R.Pout_noRIS, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Hybrid RF/FSO (no RIS)');
    semilogy(h.ax1, R.SNR_dB, R.Pout_RIS,   'r-',  'LineWidth', 2.5, 'DisplayName', ris_name);
    yline(h.ax1, P.tgt_out, 'g:', 'LineWidth', 1.5, 'Label', sprintf('Target=%.0e', P.tgt_out), 'HandleVisibility', 'off');
    if show_site
        xline(h.ax1, site_snr, 'm-.', 'LineWidth', 1.2, 'DisplayName', 'SNR at max TX power');
    end
    hold(h.ax1, 'off');
    xlabel(h.ax1, 'Average SNR (dB)', 'FontSize', 10);
    ylabel(h.ax1, 'Outage Probability P_{out}', 'FontSize', 10);
    title(h.ax1, sprintf('Outage Probability | %s | %s | N=%d', P.terrain, P.season, P.N), 'FontSize', 10);
    legend(h.ax1, 'Location', 'southwest', 'FontSize', 8);
    grid(h.ax1, 'on'); ylim(h.ax1, [1e-6 1]); xlim(h.ax1, [P.SNR_min P.SNR_max]);

    %% ── PLOT 2: Capacity ─────────────────────────────────────────────────
    cla(h.ax2);
    plot(h.ax2, R.SNR_dB, R.Cap_RF,    'k-',  'LineWidth', 1.5, 'DisplayName', 'RF Only');
    hold(h.ax2, 'on');
    plot(h.ax2, R.SNR_dB, R.Cap_noRIS, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Hybrid (no RIS)');
    plot(h.ax2, R.SNR_dB, R.Cap_RIS,   'r-',  'LineWidth', 2.5, 'DisplayName', ris_name);
    if show_site
        xline(h.ax2, site_snr, 'm-.', 'LineWidth', 1.2, 'DisplayName', 'SNR at max TX power');
    end
    hold(h.ax2, 'off');
    xlabel(h.ax2, 'Average SNR (dB)', 'FontSize', 10);
    ylabel(h.ax2, 'Ergodic Capacity C (bits/s/Hz)', 'FontSize', 10);
    title(h.ax2, sprintf('Ergodic Capacity | %s | %s | N=%d', P.terrain, P.season, P.N), 'FontSize', 10);
    legend(h.ax2, 'Location', 'northwest', 'FontSize', 8);
    grid(h.ax2, 'on'); xlim(h.ax2, [P.SNR_min P.SNR_max]);

    %% ── PLOT 3: BER ──────────────────────────────────────────────────────
    cla(h.ax3);
    semilogy(h.ax3, R.SNR_dB, R.BER_RF,    'k-',  'LineWidth', 1.5, 'DisplayName', 'RF Only');
    hold(h.ax3, 'on');
    semilogy(h.ax3, R.SNR_dB, R.BER_noRIS, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Hybrid (no RIS)');
    semilogy(h.ax3, R.SNR_dB, R.BER_RIS,   'r-',  'LineWidth', 2.5, 'DisplayName', ris_name);
    yline(h.ax3, P.tgt_ber, 'g:', 'LineWidth', 1.5, 'Label', sprintf('Target=%.0e', P.tgt_ber), 'HandleVisibility', 'off');
    if show_site
        xline(h.ax3, site_snr, 'm-.', 'LineWidth', 1.2, 'DisplayName', 'SNR at max TX power');
    end
    hold(h.ax3, 'off');
    xlabel(h.ax3, 'Average SNR (dB)', 'FontSize', 10);
    ylabel(h.ax3, 'Average BER', 'FontSize', 10);
    title(h.ax3, sprintf('Bit Error Rate (BPSK) | %s | %s | N=%d', P.terrain, P.season, P.N), 'FontSize', 10);
    legend(h.ax3, 'Location', 'southwest', 'FontSize', 8);
    grid(h.ax3, 'on'); ylim(h.ax3, [1e-6 1]); xlim(h.ax3, [P.SNR_min P.SNR_max]);
end

function update_boxes(h, R)
    C = tool_colors();
    q = R.req;  P = R.P;  LB = R.lb;

    updateResultBox(h.resultLabels{1}, box_req(q.out_ris, q.out_ris_st, P), pick(q.out_ris_st ~= -1, C.GREEN, C.RED));
    updateResultBox(h.resultLabels{2}, box_req(q.ber_ris, q.ber_ris_st, P), pick(q.ber_ris_st ~= -1, C.GREEN, C.RED));
    updateResultBox(h.resultLabels{3}, sprintf('%.2f b/s/Hz', R.mid.cap), C.BLUE);

    switch q.save_ber_kind
        case 'eq'
            updateResultBox(h.resultLabels{4}, sprintf('%.1f dB', q.save_ber), C.GREEN);
        case 'lb'
            updateResultBox(h.resultLabels{4}, sprintf('> %.1f dB', q.save_ber), C.GREEN);
        otherwise
            updateResultBox(h.resultLabels{4}, 'n/a', C.RED);
    end

    if ~isfinite(LB.ptx_ris)
        updateResultBox(h.resultLabels{5}, 'target not met', C.RED);
    elseif LB.ok_ris
        updateResultBox(h.resultLabels{5}, sprintf('%.1f dBm (closes)', LB.ptx_ris), C.GREEN);
    else
        updateResultBox(h.resultLabels{5}, sprintf('%.1f dBm (over budget)', LB.ptx_ris), C.RED);
    end

    if isfinite(R.nrec.N)
        updateResultBox(h.resultLabels{6}, sprintf('N = %d  (selected %d)', R.nrec.N, P.N), C.DARKBLUE);
    else
        updateResultBox(h.resultLabels{6}, 'n/a', C.RED);
    end
end

function s = box_req(val, st, P)
    if st == -1
        s = sprintf('> %g dB (not met)', P.SNR_max);
    elseif st == 1
        s = sprintf('<= %g dB', P.SNR_min);
    else
        s = sprintf('%.1f dB', val);
    end
end

function v = pick(cond, a, b)
    if cond, v = a; else, v = b; end
end

function rLabels = createResultBoxes(parent, C)
    titles = {'SNR for Outage Target', 'SNR for BER Target', ...
              'Capacity at Mid-SNR', 'SNR Saving (BER target)', ...
              'Required TX Power (RIS)', 'Recommended N'};
    ypos   = [208 168 128 88 48 8];
    rLabels = cell(6, 1);

    for k = 1:6
        uipanel(parent, 'Position', [7 ypos(k) 224 36], ...
            'BackgroundColor', C.WHITE, 'BorderType', 'line');
        uilabel(parent, 'Text', titles{k}, ...
            'Position', [11 ypos(k)+21 220 12], ...
            'FontSize', 8, 'FontColor', C.DARKGREY, 'FontWeight', 'bold');
        rLabels{k} = uilabel(parent, 'Text', '—', ...
            'Position', [11 ypos(k)+5 220 15], ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'FontColor', C.BLUE, 'HorizontalAlignment', 'center');
    end
end

function updateResultBox(lbl, text, color)
    set(lbl, 'Text', text, 'FontColor', color);
end

function lines = getTerrainGuide()
    lines = {
        'TERRAIN → m VALUE GUIDE'
        '------------------------------'
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
        '  Severe fading'
        ''
        'Open Savanna        m = 2.0'
        '  Matabeleland North'
        '  Near line-of-sight paths'
        '  Good fading conditions'
        ''
        'Line-of-Sight       m = 3.0'
        '  Clear rural elevated paths'
        '  Best propagation conditions'
        ''
        '------------------------------'
        'SEASON → TURBULENCE GUIDE'
        '------------------------------'
        'Dry Season (May-Sep)'
        '  α=11.6, β=10.1 (Weak)'
        ''
        'Highveld Average'
        '  α=4.0,  β=1.9  (Moderate)'
        '  Baseline conditions'
        ''
        'Rainy Season (Oct-Apr)'
        '  α=4.2,  β=1.4  (Strong)'
        ''
        '------------------------------'
        'HOW TO READ THE RESULTS'
        '------------------------------'
        '• Presets come from published'
        '  studies of similar terrain,'
        '  not from local measurement.'
        '  Use Custom to enter your own.'
        '• Figures are best-case. Add'
        '  an implementation margin on'
        '  the Link budget tab.'
        '• RIS model is validated for'
        '  N ≥ 20.'
        '• Recommended N and required'
        '  TX power are computed for'
        '  the inputs shown.'
    };
end
