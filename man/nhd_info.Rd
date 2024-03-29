% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/info.R
\name{nhd_info}
\alias{nhd_info}
\title{Return NHD layer metadata and field listing}
\usage{
nhd_info(state, dsn)
}
\arguments{
\item{state}{character}

\item{dsn}{character}
}
\value{
A column-wise summary of an sf read from the specfied layer
}
\description{
Return NHD layer metadata and field listing
}
\examples{
\dontrun{
nhd_info("DC", "NHDWaterbody")
}
}
