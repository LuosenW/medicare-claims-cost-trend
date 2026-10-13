# Data decisions log

## Source
- CMS DE-SynPUF, DE1.0 **Sample 2**. Sample 1 was not usable: CMS's Sample 1 page links its 2010 beneficiary file to Sample 20, and no Sample 1 copy of that file is available.

## Raw load checks (02_load_duckdb.R)
- Members by file year: 116,395 (2008), 114,618 (2009), 112,845 (2010).
- Orphan claims (claim member not in beneficiary file): 0 in all four claim tables.
- Claims by year drop sharply in 2010 (for example inpatient 27,451 in 2008, 25,264 in 2009, 13,515 in 2010). CMS attributes this to deaths and privacy treatment. Trend analysis focuses on 2008 to 2009; 2010 is shown and flagged.

## Duplicate claim IDs = claim segments
- Inpatient: 60 claim IDs appear twice. The second row is SEGMENT 2, which has no service dates and a different provider number. Segment 2 rows hold $1.41M of $634M inpatient paid.
- Outpatient: 11,009 claim IDs appear twice, same pattern. Segment 2 rows hold $15.1M of $225.5M outpatient paid. 192 more segment 2 rows have no matching segment 1.
- Decision: combine segments into one claim (sum paid, take the date from segment 1). Segment 2 rows with no segment 1 have no date and fall out of scope; count them in the reconciliation.

## Claims dated 2007
- 204 inpatient and 330 outpatient claims start in 2007 (care that began before the study period). Outpatient 2007 claims hold $243K paid.
- Decision: exclude from the 2008 to 2010 analysis; report the count.

## Clean table reconciliation (03_build_tables.R, first run)
- Raw paid versus clean paid: $0 difference for inpatient ($634,063,230), outpatient ($225,486,960) and pharmacy total cost ($340,970,780).
- Outpatient rows 792,562 became 781,553 claims; the 11,009 gap equals the segment pairs.
- Out of scope: 204 inpatient claims ($2,252,500, all dated 2007) and 522 outpatient claims ($575,900: 330 dated 2007 plus 192 segment 2 rows with no segment 1).
- Negative paid: 58 inpatient and 2,543 outpatient claims. Kept; these behave like normal payment adjustments.
- Zero paid: 1,967 inpatient, 29,725 outpatient, 479,943 professional. Kept; usually the member's deductible covered the cost.
- Claims paid versus CMS's annual totals on the beneficiary file: inpatient within about 2% to 5%; outpatient and professional claims run about 7% to 8% higher. The two were synthesized separately, so they are reported, not forced to match.
- Exposure (member months, fee for service only for A and B):

| Year | Members | Part A months | Part B months | Part D months |
| --- | --- | --- | --- | --- |
| 2008 | 116,395 | 1,005,405 | 944,661 | 794,888 |
| 2009 | 114,618 | 918,972 | 908,036 | 1,040,644 |
| 2010 | 112,845 | 864,262 | 834,652 | 1,099,943 |

## Pharmacy: patient pay larger than total drug cost
- What I found: 288,824 drug events (about 5%) showed a negative plan payment, because the reported patient pay was larger than the total drug cost (for example a $10 drug with a $20 copay). That cannot happen in real Part D claims.
- Why it happens: in the synthetic data, patient pay and total cost were generated almost independently (correlation about 0.27), so they do not stay consistent. The patient pay share of total cost is a steady 16.8% every year, so the issue is spread evenly and is not a trend.
- Size: about $2.1M (2008), $2.3M (2009) and $1.5M (2010) of negative plan payments, roughly 2% of drug spending.
- Options considered:
  1. Cap patient pay at total cost (chosen).
  2. Report pharmacy on total drug cost instead of plan paid.
- Why option 1: it keeps all four service categories on the same "plan paid" basis, so their PMPMs add up to a meaningful total, and it changes only about 2% of pharmacy dollars. Option 2 would mix two cost bases in one total.
- How: plan paid = total cost minus capped patient pay, never below $0. Total drug cost (allowed) is untouched, so the raw versus clean check on total cost still matches to the cent. 03_build_tables.R prints how many events were capped and how many dollars of patient pay were removed each year.

## Pharmacy cap, rerun check (03_build_tables.R, second run)
- Negative pharmacy paid is now 0. Capped events: 96,447 (2008), 115,350 (2009), 77,027 (2010), total 288,824, matching the earlier negative count exactly.
- Patient pay removed by the cap: $2,075,500 (2008), $2,326,180 (2009), $1,487,910 (2010). Plan paid after cap: $103,975,140, $113,680,660, $71,844,920.
- Zero paid pharmacy events rose from 995,829 to 1,284,653, an increase of exactly 288,824 (capped events now show $0 plan paid).

## Part D exposure grows fast (caveat for the pharmacy trend)
- Part D months rise 31% from 2008 to 2009 (794,888 to 1,040,644) while members fall, because Part D enrollment in the file grows: members with any Part D coverage go from 69,120 (2008) to 92,702 (2009) to 99,635 (2010).
- Drug events grow much less (about 9% from 2008 to 2009), so scripts per full year Part D member fall from about 32 to about 28. Pharmacy PMPM will therefore fall from 2008 to 2009 mostly because of exposure growth.
- In synthetic data, coverage and claims were generated separately, so this may not reflect real behavior. Decision: report the pharmacy trend with this caveat rather than adjust it.
- Small mismatch: some members with 0 Part D months still have drug events ($808,190 of $103,975,140 pharmacy paid in 2008, about 0.8%; $325,400 in 2009; $18,580 in 2010). Kept in the numerator; too small to change results. Reported here.
