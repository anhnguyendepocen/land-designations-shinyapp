# Copyright 2016 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

## Plot selected ecoregion/bec zone with designations
gg_ld_class <- function(class, reg_cd) {
  if (reg_cd != "BC") {
    if (class == "ecoreg") {
      ld_df <- gg_ld_x_ecoreg[gg_ld_x_ecoreg$CRGNCD == reg_cd,]
      class_df <- gg_ecoreg[gg_ecoreg$CRGNCD == reg_cd, ]
      title <- ecoreg_nms[ecoreg_ids == reg_cd]
    } else if (class == "bec") {
      ld_df <- gg_ld_x_bec[gg_ld_x_bec$ZONE == reg_cd, ]
      class_df <- gg_bec[gg_bec$ZONE == reg_cd, ]
    }
  } else {
    ld_df <- gg_ld_x_ecoreg
    class_df <- bc_bound
  }

  ggplot(ld_df, aes(x = long, y = lat, group = group)) +
    geom_polypath(data = class_df, fill = "grey80", colour = "gray80") +
    geom_polypath(aes(fill = cons_cat)) +
    scale_fill_manual(values = des_cols) +
    coord_fixed(expand = FALSE) +
    theme_map() +
    guides(fill = "none")
}

## Interactive bar chart for % designated in selected ecoregion/zone
ggiraph_barchart <- function(df, type) {
  tooltip_css = "
  color:white;
  background-color:dimgray;
  padding:5px;
  border-radius:5px;"

  hover_css <- "opacity:0.5;stroke:white;"

  df$hovertip <- paste0(des_labels[df$cons_cat],
                        "<br>Area: ",
                        format_ha_comma(df$area_des_ha),
                        " ha (",
                        format_percent(df$percent_des), "%)")
  gg <- ggplot(df[!is.na(df$cons_cat), ],
               aes(x = prot_rollup, y = percent_des)) +
    geom_bar_interactive(stat = "identity",
                         aes(fill = cons_cat, tooltip = hovertip, data_id = hovertip)) +
    scale_fill_manual(values = des_cols) +
    theme_minimal(base_size = 15) +
    theme(axis.title.x = element_text(hjust = 1)) +
    scale_y_continuous(expand = c(0,0)) +
    scale_x_discrete(expand = c(0,0), labels = prot_rollup_labels) +
    coord_flip() +
    labs(x = "Land Designation type", y = paste0("Percent of ", type, " Designated")) +
    guides(fill = "none")

  ggiraph(code = print(gg), width = 0.9, height_svg = 2.5,
          tooltip_extra_css = tooltip_css, tooltip_opacity = 0.9,
          hover_css = hover_css,
          tooltip_offx = -20)
}

## Shortcuts functions to initialize modifying ecoregion and bec leaflet maps
## (e.g., hover tips, highlight etc)
ecoreg_proxy <- function(...) leafletProxy("bc_ecoreg_map", ...)
bec_proxy <- function(...) leafletProxy("bc_bec_map", ...)

## Set view to BC
bc_view <- function(map) setView(map, lng = -126.5, lat = 54.5, zoom = 5)

## Convert & and emdashes to html strings for representing on the map
htmlize <- function(x) {
  x <- gsub("\\b&\\b", "&amp;", x, useBytes = TRUE)
  x <- gsub("--", "&mdash;", x, useBytes = TRUE)
  x
}

format_ha <- function(x) round(x, 0)
format_ha_comma <- function(x) format(x, digits = 0, big.mark = ",", scientific = FALSE)
format_percent <- function(x) round(x, 1)

highlight_clicked_poly <- function(map, clicked_polys, class) {

  if (class == "ecoreg") {
    colr <- rep("#00441b",2)
    fill <- "#006d2c"
    opac <- c(0.2, 0.8)
  } else if (class == "bec") {
    colr <- c("", "#2F4F4F")
    fill <- unname(na.omit(bec_colors[clicked_polys]))
    opac <- c(0.7, 0.9)
  }

  wts <- c(1, 2)

  if (length(clicked_polys) == 2 && clicked_polys[2] == "BC") {
    clicked_polys <- clicked_polys[1]
    wts <- wts[1]
    opac <- opac[1]
    colr <- colr[1]
  } else if (length(clicked_polys) == 2 && clicked_polys[1] == "BC") {
    clicked_polys <- clicked_polys[2]
    wts <- wts[2]
    opac <- opac[2]
    colr <- colr[2]
  } else if (length(clicked_polys) == 1) {
    wts <- wts[2]
    opac <- opac[2]
    colr <- colr[2]
  }

  addPolygons(map, layerId = clicked_polys,
              color = colr, fillColor = fill,
              weight = wts, fillOpacity = opac)
}

summarize_bec <- function(df) {
  df %>%
    group_by(Zone = ZONE, Subzone = SBZNNM, Variant = VRNTNM, `BGC Label` = MAP_LABEL,
             `Category` = cons_cat) %>%
    summarize(`Area designated (ha)` = format_ha(sum(area_des_ha, na.rm = TRUE)),
              `BGC Unit Area (ha)` = format_ha(bec_area * 1e-4),
              `Percent Designated` = format_percent((sum(area_des, na.rm = TRUE) /
                                                       sum(bec_area, na.rm = TRUE)) * 100))
}

summarize_ecoreg <- function(df) {
  df$Ecoregion <- ecoreg_nms[df$CRGNCD]
  df %>%
    group_by(Ecoregion, `Category` = cons_cat) %>%
    summarize(`Area designated (ha)` = format_ha(sum(area_des_ha, na.rm = TRUE)),
              `Ecoregion Area (ha)` = format_ha(ecoreg_area * 1e-4),
              `Percent Designated` = format_percent((sum(area_des, na.rm = TRUE) /
                                                       sum(ecoreg_area, na.rm = TRUE)) * 100))
}

format_if_exists <- function(dt, column) {
  if (column %in% names(dt$x$data)) {
    dt <- formatCurrency(dt, column, currency = "", digits = 0)
  }
  dt
}

make_dt <- function(df) {
  df[["Category"]] <- des_labels[df[["Category"]]]
  categories <- unique(df[["Category"]])
  cat_colours <- des_cols
  if (anyNA(categories)) cat_colours <- c(cat_colours, 'lightgrey')

  datatable(df, filter = "top", rownames = FALSE, options = list(pageLength = 15)) %>%
    formatStyle('Percent Designated',
                background = styleColorBar(df[["Percent Designated"]], 'green')) %>%
    formatStyle('Category', target = "cell", fontWeight = 'bold',
                color = styleEqual(categories, cat_colours)) %>%
    formatCurrency('Percent Designated', currency = "%", before = FALSE, digits = 1) %>%
    formatCurrency('Area designated (ha)', currency = "", digits = 0) %>%
    format_if_exists('Ecoregion Area (ha)') %>%
    format_if_exists('BGC Unit Area (ha)')
}

rollup_category <- function(category) {
  factor(ifelse(category %in% c("A", "B"),
                "Prot", category),
         levels = c("Prot", "C", "D"), ordered = TRUE)
}