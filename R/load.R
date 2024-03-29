#' nhd_dl_state
#'
#' @param state state abbreviation
#' @param state_exists 1 for file exists on disk
#' @param yes_dl 1 for downloading the state gdb file
#' @param file_ext file extension ("gdb", etc)
#' @param dsn name of gdb layer
#' @param wkt_filter a text string of coordinates see sf::st_read
#' @param temporary logical set FALSE to save data to a persistent
#'  rappdirs location
#' @param \dots other arguments passed to sf::st_read
#'
#' @export
#' @examples \dontrun{
#' nhd_dl_state("RI", 1, 0, NA, "NHDWaterbody")
#' }
nhd_dl_state <- function(state, state_exists, yes_dl, file_ext, dsn = NA,
                         wkt_filter = NA, temporary = FALSE, ...) {

  # print("inner")
  # print(c(state = state, state_exists = state_exists,
  #   yes_dl = yes_dl, file_ext = file_ext, dsn = dsn,
  #   wkt_filter = wkt_filter, dots = rlang::dots_list(...)))

  if (as.logical(yes_dl)) {
    nhd_get(state = state, temporary = temporary)
  }
  if (as.logical(state_exists) | as.logical(yes_dl)) {
    if (is.na(file_ext) | file_ext == "shp") {
      tryCatch(
        {
          if (!is.na(wkt_filter)) {
            if (length(rlang::dots_list(...)$query) > 0) {
              # using wkt_filter AND query
              suppressWarnings(make_valid_geom_s2(sf::st_zm(
                sf::st_read(gdb_path(state),
                  stringsAsFactors = FALSE,
                  wkt_filter = wkt_filter, query = rlang::dots_list(...)$query)
              )))
            } else {
              # using wkt_filter AND no query
              suppressWarnings(make_valid_geom_s2(sf::st_zm(
                sf::st_read(gdb_path(state), dsn,
                  stringsAsFactors = FALSE,
                  wkt_filter = wkt_filter, ...)
              )))
            }
          } else {
            if (length(rlang::dots_list(...)$query) > 0) {
              # using no wkt_filter BUT passing a query
              suppressWarnings(make_valid_geom_s2(sf::st_zm(
                sf::st_read(gdb_path(state),
                  stringsAsFactors = FALSE, query = rlang::dots_list(...)$query)
              )))
            } else {
              # using no wkt_filter AND passing no query
              suppressWarnings(make_valid_geom_s2(sf::st_zm(
                sf::st_read(gdb_path(state), dsn,
                  stringsAsFactors = FALSE, ...)
              )))
            }
          }
        },
        error = function(e) {
          # fall back to reading as non-spatial dbf
          nhd_read_dbf(state, dsn)
        })
    } else {
      if (file_ext == "gpkg") {
        if (!is_gpkg_installed()) {
          stop("The geopackage driver is not installed.")
        }
        suppressWarnings(st_read_custom(gdb_path(state), layer = dsn))
      } else {
        nhd_read_dbf(state, dsn)
      }
    }
  }
}

#' Load NHD layers into current session
#'
#' @param state character state abbreviation
#' @param dsn character name of a NHD layer
#' @param file_ext character choice of "shp" for spatial data and
#' "dbf" or "gpkg" for non-spatial. optional
#' @param approve_all_dl logical blanket approval to download all missing data.
#'  Defaults to TRUE if session is non-interactive.
#' @param temporary logical set FALSE to save data to a persistent
#'  rappdirs location
#' @param wkt_filter character. WKT spatial filter for selection.
#'  See sf::st_read
#' @param ... arguments passed to sf::st_read
#'
#' @return Spatial simple features object or data frame depending on the dsn
#' type and value passed to file_ext
#' @importFrom sf st_read gdal_utils
#' @importFrom rlang quo
#' @importFrom dplyr tbl select src_sqlite
#' @export
#'
#' @details This function will ask the user to approve downloading missing data
#'  unless approve_all_dl is set to TRUE.
#'
#' @examples \dontrun{
#' dt <- nhd_load(c("RI"), c("NHDWaterbody"))
#' dt <- nhd_load(c("CT", "RI"), "NHDWaterbody")
#' dt <- nhd_load(c("CT", "RI"), "NHDWaterbody", quiet = TRUE)
#' dt <- nhd_load("MI", "NHDFlowline")
#' dt <- nhd_load("RI", "NHDReachCrossReference")
#' dt <- nhd_load("RI", "NHDWaterbody", file_ext = "dbf")
#' dt <- nhd_load(c("RI", "DC"), "NHDWaterbody", file_ext = "gpkg")
#'
#' dt <- nhd_load("RI", "NHDWaterbody", wkt_filter = "POINT (-71.575 41.438)")
#'
#' dt <- nhd_load("RI", "NHDFlowline", pretty = FALSE, quiet = TRUE,
#'   query = paste0("SELECT * from ", "NHDFlowline", " LIMIT 1"))
#' }
nhd_load <- function(state, dsn, file_ext = NA,
                     approve_all_dl = FALSE, temporary = FALSE, wkt_filter = NA, ...) {

  if (!interactive()) {
    approve_all_dl <- TRUE
  }

  if (!(file_ext %in% c(NA, "shp", "dbf", "gpkg"))) {
    stop(paste0("file_ext must be set to either 'shp' or 'dbf'"))
  }

  nhd_state_exists <- function(state) {
    if (any(!file.exists(gdb_path(state)))) {
      state_exists <- 0
      if (!approve_all_dl) {
        userconsents <- utils::menu(c("Yes", "No"),
          title = paste0(state,
            " state gdb file not found. Download it?"))
      } else {
        userconsents <- 1
      }
      if (userconsents == 1) {
        yes_dl <- 1
      } else {
        yes_dl <- 0
      }
    } else {
      state_exists <- 1
      yes_dl <- 0
    }
    data.frame(state_exists = state_exists, yes_dl = yes_dl)
  }

  first_state_exists <- nhd_state_exists(state[1])

  if (length(state) > 1) {
    yes_dl_vec <- rbind(first_state_exists,
      do.call("rbind", lapply(state[2:length(state)],
        nhd_state_exists)))
  } else {
    yes_dl_vec <- first_state_exists
  }

  # print("outer")
  # print(c(state = state, state_exists = yes_dl_vec[1, "state_exists"],
  #   yes_dl = yes_dl_vec[1, "yes_dl"], file_ext = file_ext, dsn = dsn,
  #   wkt_filter = wkt_filter, dots = rlang::dots_list(...)))

  res <- lapply(seq_len(nrow(yes_dl_vec)),
    function(i) nhd_dl_state(state = state[i], dsn = dsn,
      yes_dl = yes_dl_vec[i, "yes_dl"],
      state_exists = yes_dl_vec[i, "state_exists"],
      file_ext = file_ext, wkt_filter = wkt_filter, ...)
  )

  res <- res[!unlist(lapply(res, is.null))]
  res <- do.call("rbind", res)

  if (!all(class(res) != "data.frame") & any(class(res) == "sf")) {
    invisible(prj <- sf::st_crs(nhd_dl_state(state = state[1], dsn = dsn,
      state_exists = first_state_exists[, "state_exists"],
      yes_dl = first_state_exists[, "yes_dl"],
      quiet = TRUE, file_ext = NA, wkt_filter = wkt_filter,
      query = paste0("SELECT * from ", dsn, " LIMIT 1"))))
    sf::st_crs(res) <- prj
  }
  res
}

#' Load NHDplus layers into current session
#'
#' @param vpu numeric vector processing unit
#' @param component character component name
#' @param dsn data source name
#' @param file_ext character choice of "shp" for spatial data and
#' "dbf" for non-spatial. optional
#' @param approve_all_dl logical blanket approval to download all missing data.
#'  Defaults to TRUE if session is non-interactive
#' @param force_dl logical force a re-download of the requested data
#' @param temporary logical set FALSE to save data to a persistent
#'  rappdirs location
#' @param pretty more minimal pretty printing st_read relative to "quiet"
#' @param wkt_filter character. WKT spatial filter for selection.
#'  See sf::st_read
#' @param ... parameters passed on to sf::st_read
#' @return spatial object
#'
#' @importFrom sf st_read st_zm
#' @importFrom foreign read.dbf
#' @importFrom curl has_internet
#' @importFrom stringr str_extract
#' @importFrom memoise memoise cache_memory
#' @importFrom digest digest
#'
#' @export
#'
#' @details This function will ask the user to approve downloading missing data
#' unless approve_all_dl is set to TRUE. Output of this function is saved in
#' active memory (memoized) to speed up repeated function calls.
#'
#' @examples \dontrun{
#' # Spatial
#' dt <- nhd_plus_load(4, "NHDSnapshot", "NHDWaterbody")
#' dt <- nhd_plus_load(c(1, 2), "NHDSnapshot", "NHDWaterbody")
#' dt <- nhd_plus_load(4, "NHDSnapshot", "NHDFlowline")
#' dt <- nhd_plus_load(4, "NHDPlusCatchment", "Catchment")
#'
#' # Quieter printing
#' dt <- nhd_plus_load(4, "NHDSnapshot", "NHDWaterbody", pretty = TRUE)
#' # Quietest printing
#' dt <- nhd_plus_load(4, "NHDSnapshot", "NHDWaterbody", quiet = TRUE)
#'
#' # Non-spatial
#' dt <- nhd_plus_load(1, "NHDPlusAttributes", "PlusFlow")
#' dt <- nhd_plus_load("National", "V1_To_V2_Crosswalk",
#'   "NHDPlusV1Network_V2Network_Crosswalk")
#' gridcode      <- nhd_plus_load(1, "NHDPlusCatchment", "featuregridcode")
#' flowline_vaa  <- nhd_plus_load(1, "NHDPlusAttributes", "PlusFlowlineVAA")
#' eromflow      <- nhd_plus_load(4, "EROMExtension", "EROM_010001")
#'
#' # Character VPU
#' plusflow <- nhd_plus_load(vpu = "10L", "NHDPlusAttributes", "PlusFlow")
#'
#' # Spatial filtering via wkt_filter
#' dt <- nhd_plus_load(4, "NHDSnapshot", "NHDWaterbody", wkt_filter = "POINT (-85.411 42.399)")
#' }
nhd_plus_load <- function(vpu, component = "NHDSnapshot", dsn,
                          file_ext = NA, approve_all_dl = FALSE,
                          force_dl = FALSE, temporary = FALSE, pretty = FALSE,
                          wkt_filter = NA, ...) {

  if (!interactive()) {
    approve_all_dl <- TRUE
  }

  if (!(file_ext %in% c(NA, "shp", "dbf"))) {
    stop(paste0("file_ext must be set to either 'shp' or 'dbf'"))
  }

  res        <- lapply(vpu, nhd_plus_load_vpu,
    component = component, dsn = dsn,
    approve_all_dl = approve_all_dl, pretty = pretty,
    temporary = temporary,
    wkt_filter = wkt_filter, ...)
  is_spatial <- unlist(lapply(res, function(x) x$is_spatial))
  # res        <- res[is_spatial]


  # resolve common names among vpus (https://github.com/jsta/nhdR/issues/57)
  names_template <- which.min(unlist(
    lapply(res, function(x) length(names(x$res)))))
  names_template <- names(res[[names_template]]$res)

  res <- lapply(res, function(x) {
    names(x$res) <- align_names(names(x$res), names_template)
    x$res <- x$res[, names_template]
    x
  })

  if (nrow(res[[1]]$res) > 0) {
    res        <- do.call("rbind", lapply(res, function(x) x$res))
  } else {
    res <- res[[1]]$res
  }

  if (any(is_spatial) & inherits(res, "data.frame")) {
    invisible(
      prj <- sf::st_crs(
        nhd_plus_load_vpu(vpu[1],
          component = component, dsn = dsn, pretty = FALSE,
          quiet = TRUE, wkt_filter = wkt_filter,
          query = paste0("SELECT * from ", dsn, " LIMIT 1"))$res
      )
    )
    sf::st_crs(res) <- prj
  }

  res
}

nhd_plus_load_vpu <- function(vpu, component, dsn, pretty, wkt_filter,
                              approve_all_dl = FALSE, force_dl = FALSE,
                              temporary = FALSE, file_ext = NA, ...) {

  vpu_path <- list.files(file.path(nhd_path(), "NHDPlus"),
    include.dirs = TRUE, full.names = TRUE)

  file_vpus <- sapply(
    stringr::str_extract(vpu_path, "_([0-9]{2}[A-z]{0,1})_"),
    function(x) substring(x, 2, nchar(x) - 1))

  vpu_path  <- vpu_path[!is.na(file_vpus)]
  file_vpus <- file_vpus[!is.na(file_vpus)]

  vpu_path <- vpu_path[file_vpus == zero_pad(vpu, 1)]

  vpu_path <- vpu_path[
    seq_len(length(vpu_path)) %in% grep("7z", vpu_path)]
  vpu_path <- vpu_path[grep(component, vpu_path)]

  if (any(!file.exists(vpu_path)) | length(vpu_path) == 0 | force_dl) {

    if (!approve_all_dl & !force_dl) {
      userconsents <- utils::menu(c("Yes", "No"),
        title = paste0(vpu,
          " vpu file not found. Download it?"))
    } else {
      userconsents <- 1
    }

    if (userconsents == 1) {
      nhd_plus_get(vpu = vpu, component = component,
        force_dl = force_dl, temporary = temporary)
    } else {
      stop("No file. Cannot load.")
    }
  }

  candidate_files <- nhd_plus_list(vpu, component = component,
    full.names = TRUE, file_ext = file_ext)
  res <- candidate_files[grep(paste0(tolower(dsn), "\\."),
    tolower(candidate_files))]
  if (length(res) == 0) {
    stop(paste0("layer '", dsn, "' not found in component '",
      component, "'"))
  }

  if (length(grep(paste0("shp", "$"), res)) > 0) {
    res <- res[grep("shp$", res)]
    res <- sf::st_zm(
      st_read_custom(res, pretty = pretty, stringsAsFactors = FALSE,
        wkt_filter = wkt_filter, ...))
    is_spatial <- TRUE
    list(res = res, is_spatial = is_spatial)
  } else {
    res <- lapply(res, foreign::read.dbf, as.is = TRUE)
    names(res) <- dsn
    is_spatial <- FALSE
    list(res = res[[dsn]], is_spatial = is_spatial)
  }
}
