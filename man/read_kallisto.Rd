% Generated by roxygen2 (4.1.1): do not edit by hand
% Please edit documentation in R/read_write.R
\name{read_kallisto}
\alias{read_kallisto}
\title{Read a kallisto data set}
\usage{
read_kallisto(output_dir, read_bootstrap = TRUE)
}
\arguments{
\item{output_dir}{the directory of the output data}

\item{read_bootstrap}{if TRUE, then searches for bootstrap data, else doesn't read it.}
}
\value{
a S3 \code{kallisto} object with the following members:
}
\description{
Read a kallisto data set
}

