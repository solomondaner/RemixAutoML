#' A version of the DT_GDL function for creating the GDL features for a new set of records
#'
#' For scoring models in production that have > 1 grouping variables and for when you need > 1 record (or records per grouping variables) returned. This function is for generating lags and moving averages (along with lags and moving averages off of time between records), for a partial set of records in your data set, typical new records that become available for model scoring. Column names and ordering will be identical to the output from the corresponding DT_GDL_Feature_Engineering() function, which most likely was used to create features for model training.
#' @author Adrian Antico
#' @family Feature Engineering
#' @param data A data.table you want to run the function on
#' @param lags A numeric vector of the specific lags you want to have generated. You must include 1 if WindowingLag = 1.
#' @param periods A numeric vector of the specific rolling statistics window sizes you want to utilize in the calculations.
#' @param statsFUNs Vector of functions for your rolling windows, such as mean, sd, min, max, quantile
#' @param statsNames A character vector of the corresponding names to create for the rollings stats variables.
#' @param targets A character vector of the column names for the reference column in which you will build your lags and rolling stats
#' @param groupingVars A character vector of categorical variable names you will build your lags and rolling stats by
#' @param sortDateName The column name of your date column used to sort events over time
#' @param timeDiffTarget Specify a desired name for features created for time between events. Set to NULL if you don't want time between events features created.
#' @param timeAgg List the time aggregation level for the time between events features, such as "hour", "day", "week", "month", "quarter", or "year"
#' @param WindowingLag Set to 0 to build rolling stats off of target columns directly or set to 1 to build the rolling stats off of the lag-1 target
#' @param Type List either "Lag" if you want features built on historical values or "Lead" if you want features built on future values
#' @param Timer Set to TRUE if you percentage complete tracker printout
#' @param SkipCols Defaults to NULL; otherwise supply a character vector of the names of columns to skip
#' @param SimpleImpute Set to TRUE for factor level imputation of "0" and numeric imputation of -1
#' @param AscRowByGroup Required to have a column with a Row Number by group (if grouping) with the smallest numbers being the records for scoring (typically the most current in time).
#' @param RecordsKeep List the number of records to retain (1 for last record, 2 for last 2 records, etc.)
#' @param AscRowRemove Set to TRUE to remove the AscRowByGroup column upon returning data.
#' @return data.table of original data plus created lags, rolling stats, and time between event lags and rolling stats
#' @examples
#' N = 25116
#' data <- data.table::data.table(DateTime = as.Date(Sys.time()),
#'   Target = stats::filter(rnorm(N,
#'                                mean = 50,
#'                                sd = 20),
#'                          filter=rep(1,10),
#'                          circular=TRUE))
#' data[, temp := seq(1:N)][, DateTime := DateTime - temp]
#' data <- data[order(DateTime)]
#' data <- Partial_DT_GDL_Feature_Engineering2(data,
#'                                             lags           = c(1:5),
#'                                             periods        = c(seq(10,50,10)),
#'                                             statsNames     = "mean",
#'                                             targets        = c("Target"),
#'                                             groupingVars   = NULL,
#'                                             sortDateName   = "DateTime",
#'                                             timeDiffTarget = c("Time_Gap"),
#'                                             timeAgg        = "days",
#'                                             WindowingLag   = 1,
#'                                             Type           = "Lag",
#'                                             Timer          = TRUE,
#'                                             SimpleImpute   = TRUE,
#'                                             AscRowByGroup  = "temp",
#'                                             RecordsKeep    = 1,
#'                                             AscRowRemove   = TRUE)
#' @export
Partial_DT_GDL_Feature_Engineering2 <- function(data,
                                                lags           = c(seq(1,5,1)),
                                                periods        = c(3,5,10,15,20,25),
                                                statsNames     = c("MA"),
                                                targets        = c("Target"),
                                                groupingVars   = NULL,
                                                sortDateName   = c("DateTime"),
                                                timeDiffTarget = c("Time_Gap"),
                                                timeAgg        = "days",
                                                WindowingLag   = 1,
                                                Type           = "Lag",
                                                Timer          = TRUE,
                                                SimpleImpute   = TRUE,
                                                AscRowByGroup  = "temp",
                                                RecordsKeep    = 1,
                                                AscRowRemove   = TRUE) {
  # Argument Checks----
  if (is.null(lags) & WindowingLag == 1) {
    lags <- 1
  }
  if (!(1 %in% lags) & WindowingLag == 1) {
    lags <- c(1, lags)
  }
  if (any(lags < 0)) {
    warning("lags need to be positive integers")
  }
  if (!is.character(statsNames)) {
    warning("statsNames needs to be a character scalar or vector")
  }
  if (!is.null(groupingVars)) {
    if (!is.character(groupingVars)) {
      warning("groupingVars needs to be a character scalar or vector")
    }
  }
  if (!is.character(targets)) {
    warning("targets needs to be a character scalar or vector")
  }
  if (!is.character(sortDateName)) {
    warning("sortDateName needs to be a character scalar or vector")
  }
  if (!is.null(timeDiffTarget)) {
    if (!is.character(timeDiffTarget)) {
      warning("timeDiffTarget needs to be a character scalar or vector")
    }
  }
  if (!is.null(timeAgg)) {
    if (!is.character(timeAgg)) {
      warning("timeAgg needs to be a character scalar or vector")
    }
  }
  if (!(WindowingLag %in% c(0, 1))) {
    warning("WindowingLag needs to be either 0 or 1")
  }
  if (!(tolower(Type) %chin% c("lag", "lead"))) {
    warning("Type needs to be either Lag or Lead")
  }
  if (!is.logical(Timer)) {
    warning("Timer needs to be TRUE or FALSE")
  }
  if (!is.logical(SimpleImpute)) {
    warning("SimpleImpute needs to be TRUE or FALSE")
  }
  if (!is.character(AscRowByGroup)) {
    warning("AscRowByGroup needs to be a character scalar for the name of your RowID column")
  }
  if (RecordsKeep < 1) {
    warning("RecordsKeep less than 1 means zero data. Why run this?")
  }
  
  # Base columns from data----
  ColKeep <- names(data)
  
  # Convert to data.table if not already----
  if (!data.table::is.data.table(data))
    data <- data.table::as.data.table(data)
  
  # Max data to keep----
  if(WindowingLag == 1) {
    MaxCols <- max(max(lags), max(periods))
  } else {
    MaxCols <- max(max(lags), max(periods) - 1)
  }
  
  # Set up counter for countdown----
  CounterIndicator <- 0
  if (!is.null(timeDiffTarget)) {
    tarNum <- length(targets) + 1
  } else {
    tarNum <- length(targets)
  }
  
  # Ensure enough columns are allocated beforehand----
  if(!is.null(groupingVars)) {
    if(MaxCols * length(groupingVars) * tarNum > data.table::truelength(data)) {
      data.table::alloc.col(DT = data, 
                            n = ncol(data) +
                              MaxCols *
                              length(groupingVars) *
                              tarNum)
    }
  } else {
    if(MaxCols * tarNum > data.table::truelength(data)) {
      data.table::alloc.col(DT = data, 
                            n = ncol(data) + 
                              MaxCols * 
                              tarNum)
    }
  }
  
  # Define total runs----
  if (!is.null(groupingVars)) {
    runs <-
      length(groupingVars) * tarNum * (length(periods) +
                                         MaxCols)
  } else {
    runs <-
      tarNum * (length(periods) +
                  MaxCols)
  }
  
  # Begin feature engineering----
  if (!is.null(groupingVars)) {
    for (i in seq_along(groupingVars)) {
      Targets <- targets
      
      # Subset data----
      data1 <- data[get(groupingVars[i]) %chin% data[get(AscRowByGroup) %in% 1:RecordsKeep][[eval(groupingVars[i])]]]
      
      # Sort data----
      if (tolower(Type) == "lag") {
        colVar <- c(groupingVars[i], sortDateName[1])
        data.table::setorderv(data1, colVar, order = 1)
      } else {
        colVar <- c(groupingVars[i], sortDateName[1])
        data.table::setorderv(data1, colVar, order = -1)
      }
      
      # Subset data for the rows needed to compute MaxCols----
      rows <- data1[, .I[get(AscRowByGroup) %in% 1:RecordsKeep]]
      Rows <- c()
      for(x in as.integer(seq_along(rows))) {
        if(x == 1) {
          Rows <- rows[x]:(rows[x]-MaxCols)
        } else {
          Rows <- c(Rows, rows[x]:(rows[x]-MaxCols))
        }
      }
      data1 <- data1[unique(Rows)]
      
      # Sort data----
      if (tolower(Type) == "lag") {
        colVar <- c(groupingVars[i], sortDateName[1])
        data.table::setorderv(data1, colVar, order = 1)
      } else {
        colVar <- c(groupingVars[i], sortDateName[1])
        data.table::setorderv(data1, colVar, order = -1)
      }
      
      # Lags----
      for (l in lags) {
        for (t in Targets) {
          data1[, paste0(groupingVars[i],
                         "_LAG_",
                         l, "_", t) := data.table::shift(get(t), 
                                                         n = l, 
                                                         type = "lag"),
                by = eval(groupingVars[i])]
          CounterIndicator <- CounterIndicator + 1
          
          # Store column names MA's and subsetting----
          if(l == 1) {
            
            # Store column names to create MA's----
            LagCols <- c(paste0(groupingVars[i],
                                "_LAG_",
                                l, "_", t))
          } else {
            
            # Store column names to create MA's----
            LagCols <- c(LagCols, paste0(groupingVars[i],
                                         "_LAG_",
                                         l, "_", t))
          }
          if (Timer) {
            print(CounterIndicator / runs)
          }
        }
      }
      
      # Time lags----
      if (!is.null(timeDiffTarget)) {
        
        # Lag the dates first----
        for (l in seq_len(MaxCols+1)) {
          data1[, paste0(groupingVars[i],
                         "TEMP",
                         l) := data.table::shift(get(sortDateName),
                                                 n = l,
                                                 type = "lag"), 
                by = eval(groupingVars[i])]
        }
        
        # Difference the lag dates----
        if (WindowingLag != 0) {
          for (l in seq_len(MaxCols)) {
            if (l == 1) {
              data1[, paste0(groupingVars[i],
                             timeDiffTarget,
                             l) := as.numeric(difftime(
                               get(sortDateName),
                               get(paste0(
                                 groupingVars[i], "TEMP", l
                               )),
                               units = eval(timeAgg)
                             )), by = eval(groupingVars[i])]
              
              # TimeLagCols----
              TimeLagCols <- c(paste0(groupingVars[i],
                                      timeDiffTarget,
                                      l))
              
              # Update----
              CounterIndicator <- CounterIndicator + 1
              if (Timer) {
                print(CounterIndicator / runs)
              }
            } else {
              data1[, paste0(groupingVars[i],
                             timeDiffTarget,
                             l) := as.numeric(difftime(get(
                               paste0(groupingVars[i], "TEMP", (l - 1))
                             ),
                             get(
                               paste0(groupingVars[i], "TEMP", l)
                             ),
                             units = eval(timeAgg))), by = eval(groupingVars[i])]
              
              # TimeLagCols----
              TimeLagCols <- c(TimeLagCols,
                               paste0(groupingVars[i],
                                      timeDiffTarget,
                                      l))
              
              # Update----
              CounterIndicator <- CounterIndicator + 1
              if (Timer) {
                print(CounterIndicator / runs)
              }
            }
          }
        } else {
          for (l in seq_along(lags)) {
            if (l == 1) {
              data1[, paste0(groupingVars[i],
                             timeDiffTarget,
                             l) := as.numeric(difftime(
                               get(sortDateName),
                               get(paste0(
                                 groupingVars[i], "TEMP", l
                               )),
                               units = eval(timeAgg)
                             )), by = eval(groupingVars[i])]
              
              # TimeLagCols----
              TimeLagCols <- c(paste0(groupingVars[i],
                                      timeDiffTarget,
                                      l))
              
              # Update----
              CounterIndicator <- CounterIndicator + 1
              if (Timer) {
                print(CounterIndicator / runs)
              }
            } else {
              data1[, paste0(groupingVars[i],
                             timeDiffTarget,
                             l) := as.numeric(difftime(get(
                               paste0(groupingVars[i], "TEMP", (l - 1))
                             ),
                             get(
                               paste0(groupingVars[i], "TEMP", l)
                             ),
                             units = eval(timeAgg))), by = eval(groupingVars[i])]
              
              # TimeLagCols----
              TimeLagCols <- c(TimeLagCols,
                               paste0(groupingVars[i],
                                      timeDiffTarget,
                                      l))
              
              # Update----
              CounterIndicator <- CounterIndicator + 1
              if (Timer) {
                print(CounterIndicator / runs)
              }
            }
          }
        }
        
        # Remove temporary lagged dates----
        for (l in seq_along(MaxCols+1)) {
          data1[, paste0(groupingVars[i], "TEMP", l) := NULL]
        }
        
        # Store new target----
        timeTarget <- paste0(groupingVars[i], timeDiffTarget, "1")
      }
      
      # Define targets----
      if (WindowingLag != 0) {
        if (!is.null(timeDiffTarget)) {
          Targets <-
            c(paste0(groupingVars[i], "_LAG_", WindowingLag, "_", Targets),
              timeTarget)
        } else {
          Targets <-
            c(paste0(groupingVars[i], "_LAG_", WindowingLag, "_", Targets))
        }
      } else {
        if (!is.null(timeDiffTarget)) {
          Targets <- c(Targets, timeTarget)
        } else {
          Targets <- Targets
        }
      }
      
      # Moving stats----
      Store <- list()
      incre <- 0L
      MA_Names <- c()
      final <- data1[temp %in% 1:RecordsKeep]
      incre <- 0
      for (j in periods) {
        for (k in seq_along(statsNames)) {
          for (t in Targets) {
            
            # Increment----
            incre <- incre + 1L
            store <- list()
            for(r in 1:RecordsKeep) {
              temprow <- data1[, .I[temp == eval(r)]]
              datatemp <- data1[temprow:(temprow - j + 1)]
              storex <- datatemp[, .(mean(get(t)))]
              store[[r]] <- data.table::setnames(
                storex, 
                "V1", 
                paste0(groupingVars[i],
                       statsNames[k],
                       "_",
                       j,
                       "_",
                       t))
            }
            
            # Store names----
            if(incre == 1) {
              MA_Names <- paste0(groupingVars[i],
                                 statsNames[k],
                                 "_",
                                 j,
                                 "_",
                                 t)
            } else {
              MA_Names <- c(MA_Names,
                            paste0(groupingVars[i],
                                   statsNames[k],
                                   "_",
                                   j,
                                   "_",
                                   t))
            }
            
            # Combine records
            final <- cbind(final, data.table::rbindlist(store))              
          }
        }
      }
      if(i == 1) {
        FinalData <- final
      } else {
        if(!is.null(timeDiffTarget)) {
          keep <- c(LagCols, TimeLagCols, MA_Names)          
        } else {
          keep <- c(LagCols, MA_Names)
        }
        FinalData <- cbind(FinalData, final[, ..keep])
      }
    }
    
    # Replace any inf values with NA----
    for (col in seq_along(FinalData)) {
      data.table::set(FinalData,
                      j = col,
                      value = replace(FinalData[[col]],
                                      is.infinite(FinalData[[col]]), NA))
    }
    
    # Turn character columns into factors----
    for (col in seq_along(FinalData)) {
      if (is.character(FinalData[[col]])) {
        data.table::set(FinalData,
                        j = col,
                        value = as.factor(FinalData[[col]]))
      }
    }
    
    # Impute missing values----
    if (SimpleImpute) {
      for (j in seq_along(FinalData)) {
        if (is.factor(FinalData[[j]])) {
          data.table::set(FinalData, which(!(
            FinalData[[j]] %in% levels(FinalData[[j]])
          )), j, "0")
        } else {
          data.table::set(FinalData,
                          which(is.na(FinalData[[j]])),
                          j,-1)
        }
      }
    }
    
    # Done----
    if(AscRowRemove) {
      return(FinalData[, eval(AscRowByGroup) := NULL])
    } else {
      return(FinalData)
    }
    
    # Non-grouping case----
  } else {
    Targets <- targets
    
    # Sort data----
    if (tolower(Type) == "lag") {
      colVar <- c(sortDateName[1])
      data.table::setorderv(data, colVar, order = 1)
    } else {
      colVar <- c(sortDateName[1])
      data.table::setorderv(data, colVar, order = -1)
    }
    
    # Subset data for the rows needed to compute MaxCols----
    rows <- data[, .I[get(AscRowByGroup) %in% 1:RecordsKeep]]
    Rows <- c()
    for(x in seq_along(rows)) {
      if(x == 1) {
        Rows <- rows[x]:(rows[x]-MaxCols)
      } else {
        Rows <- c(Rows, rows[x]:(rows[x]-MaxCols))
      }
    }
    data <- data[unique(Rows)]
    
    # Sort data----
    if (tolower(Type) == "lag") {
      colVar <- c(sortDateName[1])
      data.table::setorderv(data, colVar, order = 1)
    } else {
      colVar <- c(sortDateName[1])
      data.table::setorderv(data, colVar, order = -1)
    }
    
    # Lags----
    for (l in seq_len(MaxCols)) {
      for (t in Targets) {
        data[, paste0("LAG_",
                      l, "_", t) := data.table::shift(get(t), n = l, type = "lag")]
        CounterIndicator <- CounterIndicator + 1
        
        # Store column names MA's and subsetting----
        if(l == 1) {
          
          # Store column names to create MA's----
          LagCols <- c(paste0("LAG_",
                              l, "_", t))
          
          # Store Column Names to keep in data later----
          LagKeep <- c(paste0("LAG_",
                              l, "_", t))
        } else {
          
          # Store column names to create MA's----
          LagCols <- c(LagCols, paste0("LAG_",
                                       l, "_", t))
          
        }
        if (Timer) {
          print(CounterIndicator / runs)
        }
      }
    }
    
    # Time lags----
    if (!is.null(timeDiffTarget)) {
      
      # Lag the dates first----
      for (l in seq_len(MaxCols+1)) {
        data[, paste0("TEMP",
                      l) := data.table::shift(get(sortDateName),
                                              n = l,
                                              type = "lag")]
      }
      
      # Difference the lag dates----
      if (WindowingLag != 0) {
        for (l in seq_len(MaxCols)) {
          if (l == 1) {
            data[, paste0(timeDiffTarget,
                          l) := as.numeric(difftime(
                            get(sortDateName),
                            get(paste0("TEMP", l)),
                            units = eval(timeAgg)))]
            
            # TimeLagCols----
            TimeLagCols <- paste0(timeDiffTarget,
                                  l)
            
            # TimeLagKeep----
            TimeLagKeep <- paste0(timeDiffTarget,
                                  l)
            
            # Update----
            CounterIndicator <- CounterIndicator + 1
            if (Timer) {
              print(CounterIndicator / runs)
            }
          } else {
            data[, paste0(timeDiffTarget,
                          l) := as.numeric(difftime(get(
                            paste0("TEMP", (l - 1))
                          ),
                          get(
                            paste0("TEMP", l)
                          ),
                          units = eval(timeAgg)))]
            
            # TimeLagCols----
            TimeLagCols <- c(TimeLagCols,
                             paste0(timeDiffTarget,
                                    l))
            
            # Update----
            CounterIndicator <- CounterIndicator + 1
            if (Timer) {
              print(CounterIndicator / runs)
            }
          }
        }
      } else {
        for (l in seq_along(lags)) {
          if (l == 1) {
            data[, paste0(timeDiffTarget,
                          l) := as.numeric(difftime(
                            get(sortDateName),
                            get(paste0("TEMP", l
                            )),
                            units = eval(timeAgg)))]
            
            # TimeLagCols----
            TimeLagCols <- paste0(timeDiffTarget,
                                  l)
            
            # TimeLagKeep----
            TimeLagKeep <- paste0(timeDiffTarget,
                                  l)
            
            
            # Update----
            CounterIndicator <- CounterIndicator + 1
            if (Timer) {
              print(CounterIndicator / runs)
            }
          } else {
            data[, paste0(timeDiffTarget,
                          l) := as.numeric(difftime(get(
                            paste0("TEMP", (l - 1))
                          ),
                          get(
                            paste0("TEMP", l)
                          ),
                          units = eval(timeAgg)))]
            
            # TimeLagCols----
            TimeLagCols <- c(TimeLagCols,
                             paste0(timeDiffTarget,
                                    l))
            
            # Update----
            CounterIndicator <- CounterIndicator + 1
            if (Timer) {
              print(CounterIndicator / runs)
            }
          }
        }
      }
      
      # Remove temporary lagged dates----
      for (l in seq_along(MaxCols+1)) {
        data[, paste0("TEMP", l) := NULL]
      }
      
      # Store new target----
      timeTarget <- paste0(timeDiffTarget, "1")
    }
    
    # Define targets----
    if (WindowingLag != 0) {
      if (!is.null(timeDiffTarget)) {
        Targets <-
          c(paste0("LAG_", WindowingLag, "_", Targets),
            timeTarget)
      } else {
        Targets <-
          c(paste0("LAG_", WindowingLag, "_", Targets))
      }
    } else {
      if (!is.null(timeDiffTarget)) {
        Targets <- c(Targets, timeTarget)
      } else {
        Targets <- Targets
      }
    }
    
    # Moving stats----
    Store <- list()
    incre <- 0L
    MA_Names <- c()
    final <- data[temp %in% 1:RecordsKeep]
    incre <- 0
    for (j in periods) {
      for (k in seq_along(statsNames)) {
        for (t in Targets) {
          
          # Increment----
          incre <- incre + 1L
          store <- list()
          for(r in 1:RecordsKeep) {
            temprow <- data[, .I[temp == eval(r)]]
            datatemp <- data[temprow:(temprow - j + 1)]
            storex <- datatemp[, .(mean(get(t)))]
            store[[r]] <- data.table::setnames(
              storex, 
              "V1", 
              paste0(statsNames[k],
                     "_",
                     j,
                     "_",
                     t))
          }
          
          # Store names----
          if(incre == 1) {
            MA_Names <- paste0(statsNames[k],
                               "_",
                               j,
                               "_",
                               t)
          } else {
            MA_Names <- c(MA_Names,
                          paste0(statsNames[k],
                                 "_",
                                 j,
                                 "_",
                                 t))
          }
          
          # Something
          final <- cbind(final, data.table::rbindlist(store))              
        }
      }
    }
    
    # Final Data----
    FinalData <- final
    
    # Replace any inf values with NA----
    for (col in seq_along(FinalData)) {
      data.table::set(FinalData,
                      j = col,
                      value = replace(FinalData[[col]],
                                      is.infinite(FinalData[[col]]), NA))
    }
    
    # Turn character columns into factors----
    for (col in seq_along(FinalData)) {
      if (is.character(FinalData[[col]])) {
        data.table::set(FinalData,
                        j = col,
                        value = as.factor(FinalData[[col]]))
      }
    }
    
    # Impute missing values----
    if (SimpleImpute) {
      for (j in seq_along(FinalData)) {
        if (is.factor(FinalData[[j]])) {
          data.table::set(FinalData, which(!(
            FinalData[[j]] %in% levels(FinalData[[j]])
          )), j, "0")
        } else {
          data.table::set(FinalData,
                          which(is.na(FinalData[[j]])), j,-1)
        }
      }
    }
    
    # Done----
    if(AscRowRemove) {
      return(FinalData[, eval(AscRowByGroup) := NULL])      
    } else {
      return(FinalData)
    }
  }
}