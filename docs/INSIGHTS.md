# Key Findings

Analytical findings drawn from the `fct_county_health_metrics` and
`dim_county_demographics` mart tables. All figures are county-level
crude prevalence estimates from the CDC PLACES 2025 release (2023 data)
joined to ACS 5-Year Estimates (2022). Queries are in `/sql/`.

---

## Finding 1: Income is the strongest single predictor of diabetes burden

Counties in the lowest income quartile average **16.9% diabetes prevalence**
— nearly 50% higher than the 11.3% average in the highest income quartile.
The gradient is monotonic across all four tiers:

| Income Quartile | Avg Diabetes Prevalence | Counties |
|---|---|---|
| Q1 (lowest income) | 16.9% | 670 |
| Q2 | 14.1% | 748 |
| Q3 | 12.8% | 764 |
| Q4 (highest income) | 11.3% | 775 |

The 5.6 percentage point gap between Q1 and Q4 is large relative to the
national average of 13.6%, and holds across all 8 core chronic conditions
tested (obesity, hypertension, CHD, stroke, COPD, asthma, depression).

**Implication:** Income quartile is a reliable proxy for disease burden
at the county level. Retail pharmacy siting, mobile health programs, or
care management investments can use `income_quartile = 1` as a first-pass
filter for highest-need markets.

*Relevant query: `sql/01_rankings.sql` — Q5 (high-burden, low-income counties)*

---

## Finding 2: Insurance gaps translate directly into preventive care deficits

Counties with the highest uninsured rates (quartile 4) show dramatically
lower preventive care utilization than the best-covered counties (quartile 1):

| Uninsured Quartile | Dental Visit | Mammography | Annual Checkup |
|---|---|---|---|
| Q1 (lowest uninsured) | 64.5% | 76.3% | 78.2% |
| Q2 | 61.0% | 74.7% | 78.0% |
| Q3 | 56.9% | 73.9% | 78.1% |
| Q4 (highest uninsured) | 51.0% | 71.2% | 76.6% |

Dental visit rates show the steepest drop — a **13.5 percentage point gap**
between Q1 and Q4. Mammography follows at 5.1 points. Annual checkups are
more resilient (only 1.6 points), likely because federally qualified health
centers and community clinics maintain access even in high-uninsured areas.

The dental gap is especially notable given that PLACES captures this as a
2022 vintage measure. Counties with low dental access in 2022 also show
elevated chronic disease burden in 2023, consistent with dental health
being both a direct health outcome and a proxy for overall healthcare access.

**Implication:** Insurance coverage rate (`pct_uninsured`) is a stronger
predictor of preventive care gaps than of chronic disease prevalence alone.
Interventions targeting preventive screening should prioritize high-uninsured
counties before high-disease counties.

*Relevant queries: `sql/02_correlations.sql` — Q9 (preventive care by uninsured quartile), Q14 (cross-year dental-diabetes correlation)*

---

## Finding 3: Rural counties carry disproportionate chronic disease burden

Rural counties (population under 25,000) average **14.5% diabetes prevalence**,
compared to 11.5% in metro counties (population over 1 million) — a 3-point
gap that persists despite nearly identical annual checkup rates (~78% in
rural vs ~76% in metro).

| Population Tier | Avg Diabetes | Avg Annual Checkup | Avg % Uninsured |
|---|---|---|---|
| Rural (<25k) | 14.5% | 77.6% | 10.6% |
| Small (25k–100k) | 13.4% | 78.0% | 9.4% |
| Mid-size (100k–500k) | 11.9% | 77.8% | 8.1% |
| Large (500k–1M) | 11.3% | 76.8% | 8.1% |
| Metro (1M+) | 11.5% | 76.0% | 8.9% |

The rural checkup rate being roughly equal to metro despite higher disease burden
suggests that rural residents are engaging with primary care at comparable rates
— but are still experiencing worse outcomes. This points to upstream factors
(food environment, physical activity, economic stress) rather than care
avoidance as the primary driver.

**Implication:** Rural health interventions should focus on chronic disease
management and social determinants, not just access expansion — utilization is
not the primary bottleneck.

*Relevant query: `sql/02_correlations.sql` — Q12 (urban/rural outcomes by population tier)*

---

## Finding 4: Geographic clustering of "double burden" counties

**302 counties** sit simultaneously in the lowest income quartile (Q1) and the
highest uninsured rate quartile (Q4). These counties average:
- **17.1% diabetes prevalence** (vs 13.6% national average)
- **17.0% uninsured rate**
- **$44,611 median household income**

These counties are not evenly distributed. The five states with the highest
average county-level diabetes burden are Mississippi (17.3%), West Virginia
(17.0%), Alabama (16.8%), Louisiana (16.5%), and South Carolina (16.5%) —
all Deep South states with historically high rates of both poverty and
insurance coverage gaps.

Additionally, 185 individual counties sit 1.5 or more standard deviations
above their own state's mean diabetes prevalence — meaning they are outliers
even after controlling for their state's overall burden level. These pockets
exist in otherwise low-burden states (e.g., Alexander County, IL, z-score 4.3;
Bronx County, NY, z-score 3.9; Sioux County, ND, z-score 3.7) and represent
the highest-priority intervention targets within each state.

**Implication:** State-level averages can obscure severe county-level pockets.
A dashboard filtering on state alone will miss high-burden counties in otherwise
healthy states. The outlier detection query (Q15) is designed specifically to
surface these.

*Relevant queries: `sql/01_rankings.sql` — Q5; `sql/02_correlations.sql` — Q10; `sql/03_trends.sql` — Q15*
