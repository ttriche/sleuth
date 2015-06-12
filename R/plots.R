#' Plot bootstrap summary
#'
#' Get a d
#' @param bs_df a bootstrap summary data.frame from \code{summarize_bootstrap}
#' @param ... additional arguments to `geom_point`
#' @return a ggplot2 object
#' @export
plot_bootstrap <- function(bs_df, ...)
{
    mean_col <- grep("mean_", colnames(bs_df), value = TRUE)
    cv_col <- grep("cv_", colnames(bs_df), value = TRUE)

    ggplot(bs_df, aes_string(mean_col, cv_col)) +
        geom_point(...)
}

#' @export
prep_bs_plots <- function(obj) {
  stopifnot( is(obj, "sleuth") )

  bs <- lapply(obj[["kal"]], dcast_bootstrap, "est_counts")
  obj$dcast_bs <- bs

  obj
}

#' @export
plot_transcript_variability <- function(obj, target_id, group_string = NULL) {
  target_exp <- lapply(seq_along(obj$dcast_bs),
    function(i)
    {
      m_est <- reshape2::melt(obj$dcast_bs[[i]][target_id,],
        value.name = "est_counts")
      suppressWarnings(cbind(m_est, obj$sample_to_condition[i,]))
    }) %>%
      rbind_all()

  plt <- ggplot(target_exp, aes(sample, est_counts))

  if (is.null(group_string)) {
    plt <- plt + geom_boxplot()
  } else {
    plt <- plt + geom_boxplot(aes_string(fill = group_string))
  }

  if (!is(target_id, "character")) {
    target_id <- rownames(obj$dcast_bs[[1]])[target_id]
  }

  list(plt = plt + ggtitle(target_id), target_id = target_id)
}

#' @export
plot_transcript <- function(obj, trans_name, group_string = NULL) {
  stopifnot( is(obj, "sleuth") )

  if ( !is(trans_name, "character") ) {
    stopifnot( is(trans_name, "numeric") || is(trans_name, "integer"))
    trans_name <- rownames(obj$dcast_bs[[1]])[trans_name]
  }

  target_exp <- obj$obs_norm %>%
    filter(target_id == trans_name)

  plt <- ggplot(target_exp, aes(sample, est_counts))

  if (is.null(group_string)) {
    plt <- plt + geom_boxplot()
  } else {
    plt <- plt + geom_boxplot(aes_string(fill = group_string))
  }

  plt + ggtitle(trans_name)
}