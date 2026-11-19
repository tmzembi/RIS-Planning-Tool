# RIS Deployment Planning Tool

A MATLAB planning tool for **RIS-assisted hybrid RF/FSO relay links in rural Zimbabwe**. It evaluates end-to-end outage probability, ergodic capacity and average bit error rate behind an interactive window, converts the required average SNR into required transmit power, and reports whether the link closes within the site's power budget, so that rural network operators and planners can explore a site **without working through the underlying mathematics**.

Developed as part of a Master of Technology research project in Telecommunications and Wireless Systems at the Harare Institute of Technology (HIT), Zimbabwe.

![RIS Planning Tool GUI](docs/screenshot.png)

## What it computes

The tool models a three-stage topology: source → reconfigurable intelligent surface (RIS) → decode-and-forward relay → destination, with parallel RF and FSO links on the second hop and selection combining at the destination. RF links follow the Nakagami-m model; the FSO link follows the Gamma-Gamma turbulence model with intensity modulation and direct detection. The RIS first hop uses a central-limit approximation of the coherently combined reflected signal.

The user selects a **terrain** (sets Nakagami-m) and a **season** (sets the Gamma-Gamma parameters) from presets, or enters **custom values of m, α and β**; sets the **RIS array size** (1 to 100), the outage and BER targets, and the **link-budget inputs** (carrier frequency, hop distance, bandwidth, noise figure, antenna gains, transmit-power budget). The tool then reports:

- **Outage probability**, **ergodic capacity** and **average BER** against average SNR, for the RF-only, hybrid-without-RIS and RIS-assisted systems
- The **minimum average SNR** that meets each target, and the **SNR saving** the RIS delivers
- The **required transmit power**, the **margin against the power budget**, and whether the link closes
- The **amplifier DC power** drawn and saved
- A **recommended array size**: the smallest N whose outage-target SNR is within 0.5 dB of the N = 100 value
- **Validity notes** that say when a result lies outside the range in which the model has been checked

## Requirements

- MATLAB **R2018b or later**
- **No additional toolboxes.** Built-in functions only: `integral`, `gammainc`, `erfc`, `besselk`, `pchip`, `ppval`.
- Windows, macOS or Linux.

## Quick start

1. Download or clone this repository, or save `RIS_Planning_Tool.m` to your MATLAB working directory.
2. In the Command Window, run:

   ```matlab
   RIS_Planning_Tool
   ```

3. The window opens and runs a first computation for the baseline (Highveld Plateau, moderate turbulence, N = 50).
4. Choose terrain and season on the **Site / channel** tab, enter your link on the **Link budget** tab, and click **COMPUTE RESULTS**.
5. Click **EXPORT REPORT** to save a time-stamped text report.

### Without the window

```matlab
RIS_Planning_Tool('selftest')      % numerical self-test of the engine
RIS_Planning_Tool('validate')      % Monte Carlo check of the analytical engine
RIS_Planning_Tool('benchmark')     % run time against problem size
P = RIS_Planning_Tool('defaults'); % parameter structure
P.m = 0.5; P.alpha = 11.6; P.beta = 10.1; P.N = 20;
R = RIS_Planning_Tool(P);          % batch run, results in a structure
```

## The interface

| Panel | Contents |
|---|---|
| Left | Inputs on two tabs (Site / channel, Link budget), COMPUTE and EXPORT buttons |
| Centre-top | Three tabbed plots (outage, capacity, BER); a vertical line marks the average SNR available at full transmit power |
| Centre-bottom | Link budget summary |
| Right-top | Six key result boxes |
| Right-bottom | Terrain and season reference guide |

## From SNR to transmit power

Every curve is plotted against the average SNR per link. The link budget ties that axis to the site:

```
P_tx (dBm) = SNR (dB) + margin (dB) + L (dB) - G (dBi) + Noise (dBm)
L          = 92.45 + 20 log10(f / GHz) + 20 log10(d / km)        free-space path loss
Noise      = -174 + 10 log10(B / Hz) + NF                        receiver noise floor
```

The link **closes** when the required transmit power does not exceed the power budget. Two optional offsets move the model away from its normalised best case: an **implementation margin** (for example for channel estimation error, phase quantisation at the RIS or pointing loss) and a **RIS-path excess loss**, the amount by which a single reflected path is weaker than the reference link. Both default to 0 dB.

## Channel parameter presets

The presets are taken from published propagation studies of comparable sub-Saharan environments. **They are not fitted to measurements made in Zimbabwe.** Where local measurements exist, choose *Custom* and enter them.

### Terrain → Nakagami-m (RF links)

| Terrain category | Representative regions | m |
|---|---|---|
| Highveld Plateau *(baseline)* | Harare and surrounds, Midlands, central Mashonaland | 1.5 |
| Lowveld | Masvingo, Matabeleland South, Gonarezhou area | 1.0 |
| Eastern Highlands | Manicaland: Mutare, Nyanga, Chipinge, Vumba | 0.5 |
| Open Savanna | Matabeleland North, Hwange, Zambezi Valley | 2.0 |
| Near line-of-sight | Very flat paths with long clear sightlines | 3.0 |
| Custom | user-defined | 0.5 to 10 |

### Season → Gamma-Gamma turbulence (FSO link)

| Condition | α | β | Seasonal mapping |
|---|---|---|---|
| Weak turbulence | 11.6 | 10.1 | Dry season (May to September) |
| Moderate turbulence *(baseline)* | 4.0 | 1.9 | Year-round Highveld average |
| Strong turbulence | 4.2 | 1.4 | Rainy season (October to April) |
| Custom | 1 to 30 | 1 to 30 | user-defined |

### Fog / visibility margin (optional)

When enabled, the specific attenuation at 1550 nm is computed from the visibility with the model of Kim, McArthur and Korevaar (2001) and multiplied by the hop distance. Because the FSO branch uses direct detection, the electrical SNR falls by twice the optical attenuation in dB. The margin is a deterministic offset on the FSO branch only.

## Exported report

**EXPORT REPORT** saves `RIS_Planning_Report_YYYYMMDD_HHMMSS.txt` with the link budget summary shown on screen followed by a table of outage probability, capacity and BER at every SNR point for all three systems. A sample is in [`example/`](example/).

## Validity

- **Best case.** The model assumes perfect channel knowledge and continuous phase control at the RIS, an ideal decode-and-forward relay and no FSO pointing error. Use the implementation margin to budget for these.
- **Normalised SNR.** All links are referred to one average SNR and one hop distance. Use the RIS-path excess loss to depart from this.
- **Central-limit model.** The RIS hop is validated for N ≥ 20. Below that, results are indicative. The Gaussian tail of the model overstates outage and BER when the RIS hop is the limiting one (small m with small N, or very low targets), so the tool is conservative there and says so in its validity notes.
- **Checked against simulation.** `RIS_Planning_Tool('validate')` simulates the channel model directly (the RIS hop as the exact sum of N products of Nakagami-m amplitudes) and compares it with the analytical curves. Release check with 10^6 samples, over the points the simulation resolves to 2%:

  | Configuration | Outage | BER | Capacity |
  |---|---|---|---|
  | Highveld, moderate, N = 50 | within 1.7% | within 0.9% | within 0.1% |
  | Eastern Highlands, dry, N = 20 | within 2.1% (to 10 dB) | within 3% to 12 dB, rising to 17% at 15 dB (model conservative) | within 0.1% |

  Your figures will differ slightly because the simulation is random.
- **Not validated against field data.** No measurement campaign has been carried out. The tool is a pre-feasibility screening aid and does not replace a site survey.

## Run time

One complete analysis costs a fixed table of 6,656 Bessel-function evaluations plus six one-dimensional quadratures per SNR point. Run time is therefore linear in the number of SNR points and does not depend on N. On the authors' machine the default 41-point analysis takes about 0.06 s. `RIS_Planning_Tool('benchmark')` prints the figures for your machine.

## Version history

- **1.2.0** Corrects the BER routine (versions 1.0 and 1.1 returned 0.5 for the two hybrid systems at every SNR, so BER-based results from those versions should be discarded). Targets that are not reached are reported as not met. Adds the link budget, custom channel parameters, implementation margin, RIS-path excess loss, computed array-size recommendation, validity notes, self-test, Monte Carlo validation, benchmark and batch mode. The fog margin now uses the hop distance and the direct-detection factor of two.
- **1.1** Optional fog/visibility margin; smaller window.
- **1.0.0** First release.

## Repository contents

```
RIS_Planning_Tool.m    Single-file MATLAB application (window + analytical engine)
README.md              This file
LICENSE                MIT licence
CITATION.cff           Citation metadata
docs/screenshot.png    Window screenshot
example/               Sample exported report
```

## How to cite

> Mzembi, T., & Rushambwa, M. C. (2026). *RIS Deployment Planning Tool* (Version 1.2.0) [Computer software]. https://github.com/tmzembi/RIS-Planning-Tool

The underlying analytical framework is described in:

> Mzembi, T. (2026). *Design, Modelling, and Performance Optimisation of a RIS-Assisted Hybrid RF/FSO Communication System for Reliable Rural Connectivity in Zimbabwe* [M.Tech thesis, Harare Institute of Technology].

## Authors

- **Tinotenda Mzembi**, Harare Institute of Technology ([ORCID 0009-0007-9915-3873](https://orcid.org/0009-0007-9915-3873)), tmzembi@hit.ac.zw
- **Eng. Munyaradzi Charles Rushambwa**, Harare Institute of Technology ([ORCID 0000-0001-7452-7612](https://orcid.org/0000-0001-7452-7612))

## License

Released under the [MIT License](LICENSE). MATLAB is a proprietary product of The MathWorks, Inc.; the licence applies to the code in this repository only.
