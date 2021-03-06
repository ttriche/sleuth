#' Fit a measurement error model
#'
#' This function is a wrapper for fitting a measurement error model using
#' \code{sleuth}. It performs the technical variance estimation from the boostraps, biological
#' variance estimation, and shrinkage estimation.
#'
#' For most users, simply providing the sleuth object should be sufficient. By
#' default, this behavior will fit the full model initially specified and store
#' it in the sleuth object under 'full'.
#'
#' To see which models have been fit, users will likely find the function
#' \code{\link{models}} helpful.
#'
#' @param obj a \code{sleuth} object
#' @param formula a formula specifying the design to fit
#' @param fit_name the name to store the fit in the sleuth
#' object
#' @param ... additional arguments passed to \code{sliding_window_grouping} and
#' \code{shrink_df}
#' @return a sleuth object with updated attributes
#' @seealso \code{\link{models}} for seeing which models have been fit,
#' \code{\link{sleuth_prep}} for creating a sleuth object,
#' \code{\link{sleuth_test}} to test whether a coefficient is zero
#' @export
sleuth_fit <- function(obj, formula = NULL, fit_name = NULL, ...) {
  stopifnot( is(obj, 'sleuth') )

  if ( is.null(formula) ) {
    formula <- obj$full_formula
  } else if ( !is(formula, 'formula') ) {
    stop("'", substitute(formula), "' is not a valid 'formula'")
  }

  if ( is.null(fit_name) ) {
    fit_name <- 'full'
  } else if ( !is(fit_name, 'character') ) {
    stop("'", substitute(fit_name), "' is not a valid 'character'")
  }

  if ( length(fit_name) > 1 ) {
    stop("'", substitute(fit_name), "' is of length greater than one.",
      " Please only supply one string.")
  }

  # TODO: check if model matrix is full rank
  X <- model.matrix(formula, obj$sample_to_covariates)
  A <- solve( t(X) %*% X )

  # TODO: check if normalized. if not, normalize

  msg('summarizing bootstraps')
  # TODO: store summary in 'obj' and check if it exists so don't have to redo every time
  bs_summary <- bs_sigma_summary(obj, function(x) log(x + 0.5))

  # TODO: in normalization step, take out all things that don't pass filter so
  # don't have to filter out here
  bs_summary$obs_counts <- bs_summary$obs_counts[obj$filter_df$target_id, ]
  bs_summary$sigma_q_sq <- bs_summary$sigma_q_sq[obj$filter_df$target_id]

  msg('fitting measurement error models')

  mes <- me_model_by_row(obj, obj$design_matrix, bs_summary)
  tid <- names(mes)

  mes_df <- dplyr::bind_rows(lapply(mes,
    function(x) {
      data.frame(rss = x$rss, sigma_sq = x$sigma_sq, sigma_q_sq = x$sigma_q_sq,
        mean_obs = x$mean_obs, var_obs = x$var_obs)
    }))

  mes_df$target_id <- tid
  rm(tid)

  mes_df <- dplyr::mutate(mes_df, sigma_sq_pmax = pmax(sigma_sq, 0))

  msg('shrinkage estimation')
  swg <- sliding_window_grouping(mes_df, 'mean_obs', 'sigma_sq_pmax',
    ignore_zeroes = TRUE, ...)

  l_smooth <- shrink_df(swg, sqrt(sqrt(sigma_sq_pmax)) ~ mean_obs, 'iqr', ...)
  l_smooth <- dplyr::select(
    dplyr::mutate(l_smooth, smooth_sigma_sq = shrink ^ 4),
    -shrink)

  l_smooth <- dplyr::mutate(l_smooth,
    smooth_sigma_sq_pmax = pmax(smooth_sigma_sq, sigma_sq))


  msg('computing variance of betas')
  beta_covars <- lapply(1:nrow(l_smooth),
    function(i) {
      row <- l_smooth[i,]
      with(row,
        covar_beta(smooth_sigma_sq_pmax + sigma_q_sq, X, A)
        )
    })
  names(beta_covars) <- l_smooth$target_id

  if ( is.null(obj$fits) ) {
    obj$fits <- list()
  }

  obj$fits[[fit_name]] <- list(
    models = mes,
    summary = l_smooth,
    beta_covars = beta_covars,
    formula = formula,
    design_matrix = X)

  class(obj$fits[[fit_name]]) <- 'sleuth_model'

  obj
}

model_exists <- function(obj, which_model) {
  stopifnot( is(obj, 'sleuth') )
  stopifnot( is(which_model, 'character') )
  stopifnot( length(which_model) == 1 )

  which_model %in% names(obj$fits)
}

#' Wald test for a sleuth model
#'
#' This function computes the Wald test on one specific 'beta' coefficient on
#' every transcript.
#'
#' @param obj a \code{sleuth} object
#' @param which_beta a character string of length one denoting which beta to
#' test
#' @param which_model a character string of length one denoting which model to
#' use
#' @return an updated sleuth object
#' @seealso \code{\link{models}} to view which models have been fit and which
#' coefficients can be tested, \code{\link{wald_results}} to get back
#' a data.frame of the results
#' @export
sleuth_test <- function(obj, which_beta, which_model = 'full') {
  stopifnot( is(obj, 'sleuth') )

  if ( !model_exists(obj, which_model) ) {
    stop("'", which_model, "' is not a valid model. Please see models(",
      substitute(obj), ") for a list of fitted models")
  }

  d_matrix <- obj$fits[[which_model]]$design_matrix

  # get the beta index
  beta_i <- which(colnames(d_matrix) %in% which_beta)

  if ( length(beta_i) == 0 ) {
    stop(paste0("'", which_beta,
        "' doesn't appear in your design. Try one of the following:\n",
        colnames(d_matrix)))
  } else if ( length(beta_i) > 1 ) {
    stop(paste0("Sorry. '", which_beta, "' is ambiguous for columns: ",
        colnames(d_matrix[beta_i])))
  }

  b <- sapply(obj$fits[[ which_model ]]$models,
    function(x) {
      x$ols_fit$coefficients[ beta_i ]
    })
  names(b) <- names(obj$fits[[ which_model ]]$models)

  res <- obj$fits[[ which_model ]]$summary
  res$target_id <- as.character(res$target_id)
  res <- res[match(names(b), res$target_id), ]

  stopifnot( all.equal(res$target_id, names(b)) )

  se <- sapply(obj$fits[[ which_model ]]$beta_covars,
    function(x) {
      x[beta_i, beta_i]
    })
  se <- sqrt( se )
  se <- se[ names(b) ]

  stopifnot( all.equal(names(b), names(se)) )

  res <- dplyr::mutate(res,
    b = b,
    se_b = se,
    wald_stat = b / se,
    pval = 2 * pnorm(abs(wald_stat), lower.tail = FALSE),
    qval = p.adjust(pval, method = 'BH')
    )

  res <- dplyr::select(res, -x_group)

  if (is.null(obj$fits[[which_model]]$wald)) {
    obj$fits[[which_model]]$wald <- list()
  }

  obj$fits[[which_model]]$wald[[which_beta]] <- res

  obj
}

# Compute the covariance on beta under OLS
#
# Compute the covariance on beta under OLS
# @param sigma a numeric of either length 1 or nrow(X) defining the variance
# on D_i
# @param X the design matrix
# @param A inv(t(X) X) (for speedup)
# @return a covariance matrix on beta
covar_beta <- function(sigma, X, A) {
  if (length(sigma) == 1) {
    return( sigma * A )
  }

  # sammich!
  A %*% (t(X) %*% diag(sigma) %*% X) %*% A
}

# Measurement error model
#
# Fit the measurement error model across all samples
#
# @param obj a \code{sleuth} object
# @param design a design matrix
# @param bs_summary a list from \code{bs_sigma_summary}
# @return a list with a bunch of objects that are useful for shrinking
me_model_by_row <- function(obj, design, bs_summary) {
  stopifnot( is(obj, "sleuth") )

  stopifnot( all.equal(names(bs_summary$sigma_q_sq), rownames(bs_summary$obs_counts)) )
  stopifnot( length(bs_summary$sigma_q_sq) == nrow(bs_summary$obs_counts))

  models <- lapply(1:nrow(bs_summary$obs_counts),
    function(i)
    {
      me_model(design, bs_summary$obs_counts[i,], bs_summary$sigma_q_sq[i])
    })
  names(models) <- rownames(bs_summary$obs_counts)

  models
}

# non-equal var
#
# word
#
# @param obj a sleuth object
# @param design a design matrix
# @param samp_bs_summary the sample boostrap summary computed by sleuth_summarize_bootstrap_col
# @return a list with a bunch of objects used for shrinkage :)
me_heteroscedastic_by_row <- function(obj, design, samp_bs_summary, obs_counts) {
  stopifnot( is(obj, "sleuth") )

  cat("dcasting...\n")
  sigma_q_sq <- dcast(
    select(samp_bs_summary, target_id, bs_var_est_counts, sample),
    target_id ~ sample,
    value.var  = "bs_var_est_counts")
  sigma_q_sq <- as.data.frame(sigma_q_sq)
  rownames(sigma_q_sq) <- sigma_q_sq$target_id
  sigma_q_sq$target_id <- NULL
  sigma_q_sq <- as.matrix(sigma_q_sq)

  stopifnot( all.equal(rownames(sigma_q_sq), rownames(obs_counts)) )
  stopifnot( dim(sigma_q_sq) == dim(obs_counts))

  X <- design
  A <- solve(t(X) %*% X) %*% t(X)

  models <- lapply(1:nrow(bs_summary$obs_counts),
    function(i) {
      res <- me_white_model(design, obs_counts[i,], sigma_q_sq[i,], A)
      res$df$target_id = rownames(obs_counts)[i]
      res
    })
  names(models) <- rownames(obs_counts)

  models
}


me_white_model <- function(X, y, bs_sigma_sq, A) {
  n <- nrow(X)
  degrees_free <- n - ncol(X)

  ols_fit <- lm.fit(X, y)

  # estimate of sigma_i^2 + sigma_{qi}^2
  r_sq <- ols_fit$residuals ^ 2
  sigma_sq <- r_sq - bs_sigma_sq

  mean_obs <- mean(y)
  var_obs <- var(y)

  df <- data.frame(mean_obs = mean_obs, var_obs = var_obs,
    sigma_q_sq = bs_sigma_sq, sigma_sq = sigma_sq, r_sq = r_sq,
    sample = names(bs_sigma_sq))

  list(
    ols = ols_fit,
    r_sq = r_sq,
    sigma_sq = sigma_sq,
    bs_sigma_sq = bs_sigma_sq,
    mean_obs = mean_obs,
    var_obs = var_obs,
    df = df
    )
}

me_white_var <- function(df, sigma_col, sigma_q_col, X, tXX_inv) {
  # TODO: ensure X is in the same order as df
  sigma <- df[[sigma_col]] + df[[sigma_q_col]]
  df <- mutate(df, sigma = sigma)
  beta_var <- tXX_inv %*% (t(X) %*% diag(df$sigma) %*% X) %*% tXX_inv

  res <- as.data.frame(t(diag(beta_var)))
  res$target_id <- df$target_id[1]

  res
}

#' @export
bs_sigma_summary <- function(obj, transform = identity) {
  obs_counts <- obs_to_matrix(obj, "est_counts")
  obs_counts <- transform( obs_counts )

  bs_summary <- sleuth_summarize_bootstrap_col(obj, "est_counts", transform)
  bs_summary <- dplyr::group_by(bs_summary, target_id)
  bs_summary <- dplyr::summarise(bs_summary,
    sigma_q_sq = mean(bs_var_est_counts))

  bs_summary <- as_df(bs_summary)

  bs_sigma <- bs_summary$sigma_q_sq
  names(bs_sigma) <- bs_summary$target_id
  bs_sigma <- bs_sigma[rownames(obs_counts)]

  list(obs_counts = obs_counts, sigma_q_sq = bs_sigma)
}

me_model <- function(X, y, sigma_q_sq)
{
  n <- nrow(X)
  degrees_free <- n - ncol(X)

  ols_fit <- lm.fit(X, y)
  rss <- sum(ols_fit$residuals ^ 2)
  sigma_sq <- rss / (degrees_free) - sigma_q_sq

  mean_obs <- mean(y)
  var_obs <- var(y)

  list(
    ols_fit = ols_fit,
    b1 = ols_fit$coefficients[2],
    rss = rss,
    sigma_sq = sigma_sq,
    sigma_q_sq = sigma_q_sq,
    mean_obs = mean_obs,
    var_obs = var_obs
    )
}
