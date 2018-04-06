library(tidyverse)
library(rvest)
library(rio)

# set ggplot2 theme
theme_set(ggthemes::theme_few())

# import table with URLs for team-season observations
sis_overview <- import("table_scrape_overview.xlsx") %>% 
  filter(!is.na(url))

# loop through sis_overview and get all matches as a dataframe
df_total <- data.frame()
for (i in 1:nrow(sis_overview)) {
  url_use <- sis_overview$url[[i]]
  sis_table <-  url_use %>% 
    read_html() %>%
    html_nodes(xpath='//*[@id="ctl00_ContentPlaceHolder1_Panel1"]/div[4]/table') %>%
    html_table() %>% 
    as.data.frame() %>% 
    mutate(season = sis_overview$Saison[[i]],
           team = sis_overview$team[[i]],
           league = sis_overview$league[[i]],
           place = sis_overview$place[[i]],
           points_won = sis_overview$points_won[[i]],
           points_lost = sis_overview$points_lost[[i]])
  
  df_total <- rbind(df_total, sis_table)

}

# save file
write_csv(df_total, "tsv_scraped.csv")

# open raw dataset
df_total <- read_csv("tsv_scraped.csv")

nrow(df_total)

# tidy up data frame
sis_tidy <- df_total %>% 
  select(c(Nr, Datum, Zeit, Heim, Gast, Tore, Punkte, season, team, league, place, points_won, points_lost)) %>% 
  mutate(game_id = paste(season, Nr, sep = "_")) %>% 
  separate(Tore, into = c("goals_home", "goals_away"), sep = ":") %>% 
  mutate(result = if_else(goals_home > goals_away, "Sieg Heimmannschaft",
                          if_else(goals_home < goals_away, "Sieg Auswärtsmannschaft", "Unentschieden")))
  
# convert to long format        
sis_long <- sis_tidy %>% 
  gather(key = match_type, value = team_league, -c(Nr, game_id, team, season, Datum, Zeit, 
                                            goals_home, goals_away, result, league, Punkte, Nr,
                                            season, place, points_won, points_lost)) 

# clean names of TSV teams
sis_long <- sis_long %>% 
  mutate(team_league_clean = if_else(grepl("TSV Bonn rrh.", team_league), "TSV Bonn rrh.", team_league)) %>% 
  mutate(tsv_dummy = if_else(team_league_clean == "TSV Bonn rrh.", "TSV Bonn rrh.", "Gegner")) %>% 
  mutate(result_num = if_else(result == "Sieg Heimmannschaft", 1, 
                              if_else(result == "Sieg Auswärtsmannschaft", 0, 0.5))) %>% 
  mutate(male_female = if_else(grepl("Herren", team), "Herren", "Damen"))


# calculate home advantage
sis_home_advantage <- sis_long %>% 
  group_by(season, team_league, league) %>% ## important!
  mutate(Mean = mean(result_num, na.rm = TRUE)) %>% 
  select(season, Mean, tsv_dummy, place, team_league, team, team_league_clean, male_female, league) %>% 
  unique() %>% 
  mutate(pos_neg = if_else(Mean < 0.5, "negative", "positive"))


sis_home_advantage %>% 
  arrange(Mean) %>% 
  tail()

ggplot(sis_home_advantage, aes(x = tsv_dummy, y  = Mean)) +
  geom_boxplot() +
  ggbeeswarm::geom_quasirandom()

library(ggridges)

sis_home_advantage <- sis_home_advantage %>% 
  mutate(remove = if_else(team_league == "TSV Bonn rrh. 2" & team == "3. Herren", TRUE,
                          if_else(team_league == "TSV Bonn rrh. 3" & team == "2. Herren", TRUE, FALSE))) %>% 
  filter(remove == FALSE)

sis_home_advantage$tsv_dummy <- factor(sis_home_advantage$tsv_dummy,
                                       levels = c("TSV Bonn rrh.", "Gegner"))
sis_home_advantage %>% 
  filter(male_female == "Herren") %>% 
  ggplot(aes(x = Mean, y = tsv_dummy)) +
  geom_density_ridges(jittered_points = TRUE,
                      quantile_lines = TRUE, quantiles = 2, fill = "grey90",
                      position = position_points_jitter(width = 0.05, height = 0),
                      point_shape = '|', point_size = 3, alpha = 0.7) +
  facet_wrap(~team) +
  scale_x_continuous(limits = c(0, 1)) +
  labs(x = "Heimvorteil", y = NULL)

sis_home_advantage %>% 
  filter(male_female == "Damen") %>% 
  ggplot(aes(x = Mean, y = tsv_dummy)) +
  geom_density_ridges(jittered_points = TRUE,
                      quantile_lines = TRUE, quantiles = 2, fill = "grey90",
                      position = position_points_jitter(width = 0.05, height = 0),
                      point_shape = '|', point_size = 3, alpha = 0.7) +
  facet_wrap(~team) +
  scale_x_continuous(limits = c(0, 1)) +
  labs(x = "Heimvorteil", y = NULL)

sis_home_advantage_tsv <- sis_home_advantage %>%
  filter(team_league_clean == "TSV Bonn rrh.")  %>% 
  filter(!team_league %in% c("TSV Bonn rrh. Fr. 3", "TSV Bonn rrh. F3"))

gg_heimvorteil <- function(data = sis_home_advantage_tsv, gender = c("Herren", "Damen")) {
  sis_home_advantage_tsv %>% 
    filter(male_female %in% gender) %>% 
    ggplot(aes(x = Mean, y = season, colour = pos_neg)) +
  geom_point() +
  geom_segment(aes(x = 0.5, y = season, xend = Mean, yend = season)) +
  geom_vline(xintercept = 0.5, linetype = "dotted") +
  scale_fill_brewer(palette = "Set1") +
  scale_x_continuous(limits = c(0.1, 0.8)) +
  labs(x = "Heimvorteil", y = NULL) +
  facet_wrap(~team) +
  theme(legend.position = "none")
}

gg_heimvorteil(gender = "Herren")

gg_heimvorteil(gender = "Damen")


sis_home_advantage %>% 
  filter(tsv_dummy == "TSV Bonn rrh.") %>% 
  ggplot(aes(x = place, y = Mean)) +
  geom_point() +
  theme(legend.position = "bottom") +
  scale_x_continuous(limits = c(1, max(sis_home_advantage$place, na.rm = TRUE) + 1), 
                     breaks = c(seq(1, max(sis_home_advantage$place, na.rm = TRUE) + 1, 2))) +
  facet_wrap(~team)

sis_home_advantage_wide <- sis_home_advantage %>% 
  select(season, league, tsv_dummy, Mean) %>% 
  spread(key = tsv_dummy, value = Mean) %>% 
  mutate(diff_home_advantage = `TSV Bonn rrh.` - `Rest der Liga`)

ggplot(sis_home_advantage_wide, aes(x = season, y = diff_home_advantage)) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  coord_flip() +
  facet_grid(league~team) 

