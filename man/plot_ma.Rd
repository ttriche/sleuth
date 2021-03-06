% Generated by roxygen2 (4.1.1): do not edit by hand
% Please edit documentation in R/plots.R
\name{plot_ma}
\alias{plot_ma}
\title{MA plot}
\usage{
plot_ma(obj, which_beta, which_model = "full", sig_level = 0.1,
  point_alpha = 0.2, sig_color = "red", highlight = NULL,
  highlight_color = "green")
}
\arguments{
\item{obj}{a \code{sleuth} object}

\item{which_beta}{a character string denoting which beta to use for
highlighting the transcript}

\item{which_model}{a character string denoting which model to use for the
test}

\item{point_alpha}{the alpha for the points}
}
\value{
a \code{ggplot2} object
}
\description{
Make an 'MA plot' for a given test. MA plots display, for each transcript, the mean of abundances across samples on the
x-axis and fold change on the y-axis.
}

