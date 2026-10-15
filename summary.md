# Why did health care costs go up? A one page summary

**Luosen Wei** | Medicare claims cost and use analysis | Synthetic CMS data, 2008 to 2010

## The headline

Most of the rise in medical costs from 2008 to 2009 came from people using more care, not from care getting more expensive.

## The question

A health plan pays for its members' doctor visits, hospital stays and prescriptions. Each year it needs to know how much each member costs, why that changed, and where to focus to keep costs in check. I answered those questions for about 116,000 members using 11 million claim records.

## What I found

- **Cost per member went up 6%.** The plan paid an average of $624 per member each month in 2008 and $664 in 2009.
- **More care, not higher prices, drove most of the medical increase.** Medical costs (hospital, outpatient and doctor care) rose $61 per member each month. About $39 of that came from members using more services, mainly outpatient visits and doctor services. About $22 came from higher prices per service. Hospital stays were the exception: the number of stays stayed flat, but each stay cost about 5% more.
- **A small group of members drives most of the cost.** In 2008 the costliest 5% of members accounted for 41% of all spending. In 2009 the costliest 1% averaged $64,000 each, compared with about $4,800 for everyone else, and three quarters of their cost was hospital care.
- **Chronic illness multiplies cost.** Members with 6 or more long term conditions (such as diabetes, heart failure or kidney disease) cost about $1,700 a month, about 14 times as much as members with none.
- **Drug costs looked like they fell 17%, but that was misleading.** Many more members joined drug coverage while the number of prescriptions grew much less, which spread the same spending across more people. The price per prescription barely changed.

![What drove the 2008 to 2009 change in cost per member](output/charts/03_trend_drivers_2009.png)

## What a plan could do with this

- **Focus care management on the few members with the highest costs.** Helping the top 1% avoid hospital stays would have the biggest effect on total spending.
- **Look into the rise in outpatient and doctor visits.** Since use, not price, drove most of the increase, it is worth checking which services grew and whether that care was needed.
- **Check who is covered before reading a trend.** The drug result shows that a change in who is enrolled can look like a change in cost.

## About the data

This uses synthetic (made up but realistic) Medicare claims that CMS publishes for training. The numbers show the method a health plan would use on real claims, not real Medicare results. 2010 records are incomplete, so the comparison focuses on 2008 and 2009. Full details, code and the dashboard are in this repository.
