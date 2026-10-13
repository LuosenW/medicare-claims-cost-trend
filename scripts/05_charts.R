# 05_charts.R
# Makes the README charts from the exported CSVs in output/tables.

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)

tab <- file.path("output", "tables")
fig <- file.path("output", "charts")
dir.create(fig, recursive = TRUE, showWarnings = FALSE)

cat_year <- read_csv(file.path(tab, "category_year.csv"), show_col_types = FALSE)
trend    <- read_csv(file.path(tab, "trend.csv"), show_col_types = FALSE)
conc     <- read_csv(file.path(tab, "cost_concentration.csv"), show_col_types = FALSE) |>
  mutate(cum_share_of_cost = pmin(cum_share_of_cost, 1))  # rounding pushes the last points a hair above 100%
chronic  <- read_csv(file.path(tab, "chronic.csv"), show_col_types = FALSE)

cat_levels <- c("Inpatient", "Outpatient", "Professional", "Pharmacy")
cat_colors <- c(Inpatient = "#1f4e79", Outpatient = "#4a90c2", Professional = "#9cc3e4", Pharmacy = "#e08a3c")
theme_set(theme_minimal(base_size = 12) + theme(panel.grid.minor = element_blank()))
note_2010 <- "2010 claims are incomplete in the source data (CMS notes attrition and privacy treatment)."

# 1. PMPM by service category and year (stacked: categories add up to total PMPM)
p1 <- cat_year |>
  mutate(service_category = factor(service_category, levels = rev(cat_levels))) |>
  ggplot(aes(factor(year), paid_pmpm, fill = service_category)) +
  geom_col(width = 0.6) +
  scale_fill_manual(values = cat_colors, breaks = cat_levels) +
  scale_y_continuous(labels = dollar) +
  labs(title = "Paid cost per member per month rose 6% from 2008 to 2009",
       subtitle = "$624 in 2008 and $664 in 2009; 2010 is shown but its claims are incomplete",
       x = NULL, y = "Paid per member per month",
       fill = NULL, caption = note_2010)
ggsave(file.path(fig, "01_pmpm_by_category.png"), p1, width = 8, height = 5, dpi = 200)

# 2. Utilization per 1,000 by category over time (each on its own scale)
p2 <- cat_year |>
  mutate(service_category = factor(paste0(service_category, " (", unit_label, ")"),
                                   levels = paste0(cat_levels, " (", c("Admissions", "Visits", "Services", "Scripts"), ")"))) |>
  ggplot(aes(year, util_per_1000)) +
  geom_line(data = ~ filter(.x, year <= 2009), color = "#1f4e79", linewidth = 1) +
  geom_line(data = ~ filter(.x, year >= 2009), color = "grey65", linewidth = 1, linetype = "dashed") +
  geom_point(aes(color = year == 2010), size = 2, show.legend = FALSE) +
  scale_color_manual(values = c(`FALSE` = "#1f4e79", `TRUE` = "grey65")) +
  facet_wrap(~service_category, scales = "free_y") +
  scale_x_continuous(breaks = 2008:2010) +
  scale_y_continuous(labels = comma) +
  labs(title = "Outpatient and physician use rose in 2009; inpatient admissions held flat",
       subtitle = "Utilization per 1,000 members per year; dashed grey = 2010, incomplete in the source data",
       x = NULL, y = NULL, caption = "Pharmacy scripts per 1,000 fall mainly because Part D enrollment grew faster than drug claims.")
ggsave(file.path(fig, "02_util_per_1000.png"), p2, width = 9, height = 6, dpi = 200)

# 3. 2009 vs 2008 PMPM change split into utilization and unit cost effects
p3 <- trend |>
  filter(year == 2009) |>
  select(service_category, Utilization = util_effect_pmpm, `Unit cost` = unit_cost_effect_pmpm) |>
  pivot_longer(-service_category, names_to = "driver", values_to = "pmpm_effect") |>
  mutate(service_category = factor(service_category, levels = cat_levels)) |>
  ggplot(aes(service_category, pmpm_effect, fill = driver)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  geom_hline(yintercept = 0, color = "grey30") +
  scale_fill_manual(values = c(Utilization = "#1f4e79", `Unit cost` = "#e08a3c"), breaks = c("Utilization", "Unit cost")) +
  scale_y_continuous(labels = dollar) +
  labs(title = "Higher use drove about two thirds of the 2009 medical cost increase",
       subtitle = "Dollar change in paid PMPM from more (or less) use versus higher (or lower) cost per service",
       x = NULL, y = "Change in paid PMPM", fill = NULL,
       caption = "Pharmacy's drop reflects Part D enrollment growing faster than drug claims, not lower use per person.")
ggsave(file.path(fig, "03_trend_drivers_2009.png"), p3, width = 8, height = 5, dpi = 200)

# 4. Cost concentration curve
p4 <- conc |>
  filter(year %in% c(2008, 2009)) |>
  ggplot(aes(top_pct_of_members, cum_share_of_cost, color = factor(year))) +
  geom_line(linewidth = 1) +
  geom_abline(slope = 0.01, intercept = 0, linetype = "dashed", color = "grey50") +
  scale_x_continuous(labels = function(x) paste0(x, "%"), breaks = seq(0, 100, 10)) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_color_manual(values = c(`2008` = "#9cc3e4", `2009` = "#1f4e79")) +
  annotate("point", x = 5, y = 0.4125, color = "#1f4e79", size = 2.5) +
  annotate("text", x = 7, y = 0.39, hjust = 0, size = 3.8,
           label = "Top 5% = 41% of cost") +
  labs(title = "5% of members drove 41% of 2008 cost",
       subtitle = "Members ranked from highest to lowest annual paid; dashed line = cost spread evenly",
       x = "Top % of members", y = "Share of total paid", color = NULL)
ggsave(file.path(fig, "04_cost_concentration.png"), p4, width = 8, height = 5, dpi = 200)

# 5. PMPM by number of chronic conditions (2009)
p5 <- chronic |>
  filter(year == 2009) |>
  mutate(chronic_conditions = factor(chronic_conditions, levels = c(as.character(0:5), "6+"))) |>
  pivot_longer(c(medical_pmpm, pharmacy_pmpm), names_to = "type", values_to = "pmpm") |>
  mutate(type = recode(type, medical_pmpm = "Medical", pharmacy_pmpm = "Pharmacy")) |>
  ggplot(aes(chronic_conditions, pmpm, fill = type)) +
  geom_col(width = 0.65) +
  scale_fill_manual(values = c(Medical = "#1f4e79", Pharmacy = "#e08a3c")) +
  scale_y_continuous(labels = dollar) +
  labs(title = "6+ chronic conditions: about 14 times the cost of members with none (2009)",
       subtitle = "$1,712 vs $124 per member per month. 16% of members have 6 or more.",
       x = "Number of chronic conditions (of 11 tracked)", y = "Paid PMPM", fill = NULL)
ggsave(file.path(fig, "05_pmpm_by_chronic.png"), p5, width = 8, height = 5, dpi = 200)

message("Charts saved to ", fig)
