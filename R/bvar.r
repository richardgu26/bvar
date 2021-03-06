#' @export
bvar <- function(mydata,NoLags=1,Intercept=TRUE,RandomWalk=TRUE,prior=1,priorparam,irfhorizon=16,irfquantiles=c(0.1,0.9),ident=1,Restrictions=NULL,nreps=110,burnin=10,stabletest=TRUE){
  ###############################
  #
  # Declare Variables
  #
  ###############################

  Y <- as.matrix(mydata)
  T <- nrow(Y)
  K <- ncol(Y)
  obs <- T-NoLags
  constant <- 0
  if(Intercept==TRUE) constant=1

  # Variables for storage
  betadraws <- array(0,dim=c(K*NoLags+constant,K,nreps-burnin))
  sigmadraws <- array(0,dim=c(K,K,nreps-burnin))
  irfdraws <- array(0,dim=c(K,K,irfhorizon,nreps-burnin))
  irffinal <- array(0,dim=c(K,K,irfhorizon,3))

  ##############################
  #
  # Check if input is correct
  #
  ##############################
  if(prior>4){
    stop("Invalid choice for prior")
  }
  if(ident>2){
    stop("Invalid choice for identification of structural shocks")
  }

  ##############################
  #
  # Create prior
  #
  ##############################
  if(prior==1){
    # Independent Normal-Wishart Prior
	if(isempty(priorparam)){
	  stop("No prior parameters for Independent Normal-Wishart prior")
	}
	coefprior    <- priorparam[[1]]
	coefpriorvar <- priorparam[[2]]
	varprior     <- priorparam[[3]]
	varpriordof  <- priorparam[[4]]
	
    pr <- niprior(K=K,NoLags=NoLags,RandomWalk=RandomWalk,Intercept=Intercept,coefprior=coefprior,coefpriorvar=coefpriorvar,varprior=varprior)

    aprior <- as.vector(pr$coefprior)
    Vprior <- pr$coefpriorvar
    vprior <- varpriordof
    Sprior <- pr$varprior
  }
  else if(prior==2){
    # Minnesota Prior
	if(isempty(priorparam)){
	  stop("No prior parameters for Independent Normal-Wishart prior")
	}
	else{
	  lambda1 <- priorparam[[1]]
	  lambda2 <- priorparam[[2]]
	  lambda3 <- priorparam[[3]]
	}
	
    pr <- mbprior(y=mydata,NoLags=NoLags,Intercept=Intercept,RandomWalk=RandomWalk,lambda1=lambda1,lambda2=lambda2,lambda3=lambda3)
    aprior <- pr$aprior
    Vprior <- pr$Vmatrix
  }
  else if(prior==3){
    if(isempty(priorparam)){
	  stop("No prior parameters for Natural conjugate prior")
	}
	coefprior    <- priorparam[[1]]
	coefpriorvar <- priorparam[[2]]
	varprior     <- priorparam[[3]]
	varpriordof  <- priorparam[[4]]
    # Natural Conjugate Prior
    pr <- ncprior(K=K,NoLags=NoLags,RandomWalk=RandomWalk,Intercept=Intercept,coefprior=coefprior,coefpriorvar=coefpriorvar,varprior=varprior)

    aprior <- pr$coefprior
    Vprior <- pr$coefpriorvar
    vprior <- varpriordof
    Sprior <- pr$varprior
  }
  else if(prior==4){
    # Uninformative prior, do nothing
  }


  ######################################
  #
  # Initialize the MCMC algorithm
  #
  ######################################

  # lag data
  dat <- lagdata(Y,lags=NoLags,intercept=Intercept)
  y.lagged <- dat$y
  x.lagged <- dat$x

  # OLS estimates
  Aols <- solve(t(x.lagged)%*%x.lagged)%*%t(x.lagged)%*%y.lagged
  aols <- as.vector(Aols)
  resi <- y.lagged-x.lagged%*%Aols
  SSE  <- t(resi)%*%resi
  Sigma <- SSE/T

  ######################################
  #
  # Start Gibbs Sampling
  #
  ######################################
  for(irep in 1:nreps){
    print(irep)
    #readline(prompt="Press [enter] to continue")
    if(prior==1){
      postdraw <- postni(y=y.lagged,x=x.lagged,aprior=aprior,Vprior=Vprior,vprior=vprior,Sprior=Sprior,Sigma=Sigma,stabletest=TRUE,Intercept=Intercept,NoLags=NoLags)
      Alpha <- postdraw$Alpha
      Sigma <- postdraw$Sigma
    }
    else if(prior==2){
      postdraw <- postmb(y=y.lagged,x=x.lagged,Vprior=Vprior,aprior=aprior,Sigma=Sigma,betaols=aols)
      Alpha <- postdraw$Alpha
      Sigma <- postdraw$Sigma
    }
	else if(prior==3){
	  postdraw <- postnc(y=y.lagged,x=x.lagged,aprior=aprior,Vprior=Vprior,vprior=vprior,Sprior=Sprior,Sigma=Sigma,stabletest=TRUE,Intercept=Intercept,NoLags=NoLags)
	  Alpha <- postdraw$Alpha
	  Sigma <- postdraw$Sigma 
	}
	else if(prior==4){
	  postdraw <- postun(y=y.lagged,x=x.lagged,Sigma=Sigma,stabletest=TRUE,Intercept=Intercept,NoLags=NoLags)
	  Alpha <- postdraw$Alpha
	  Sigma <- postdraw$Sigma 
	}

    if(irep>burnin){
      # compute and save impulse-response functions
      if(ident==1){
        # Recursive identification
        irf <- compirf(A=Alpha,Sigma=Sigma,NoLags=NoLags,intercept=Intercept,nhor=irfhorizon)
      }
      else if(ident==2){
        # Identification using Sign restrictions
		if(is.null(Restrictions)){
		  stop("No Restrictions provided")
		}
		irf <- compirfsign(A=Alpha,Sigma=Sigma,NoLags=NoLgas,intercept=Intercept,nhor=irfhorizon,restrictions=Restrictions)
      }
      irfdraws[,,,irep-burnin] <- irf
      #plot(irf[1,1,],type="l")

      # save draws
      betadraws[,,irep-burnin] <- Alpha
      sigmadraws[,,irep-burnin] <- Sigma

    }
  }
  # Final computations
  irffinal <- array(0,dim=c(K,K,irfhor,h,3))
  irflower <- min(irfquantiles)
  irfupper <- max(irfquantiles)
  for(jj in 1:K){
    for(kk in 1:K){
      for(ll in 1:irfhor){
        irffinal[jj,kk,ll,ii,1] <- mean(irfdraws[jj,kk,ll,ii,])
        irffinal[jj,kk,ll,ii,2] <- quantile(irfdraws[jj,kk,ll,ii,],probs=irflower)
        irffinal[jj,kk,ll,ii,3] <- quantile(irfdraws[jj,kk,ll,ii,],probs=irfupper)
      }
    }
  }
  
  relist <- list(type=prior,betadraws=betadraws,sigmadraws=sigmadraws,irfdraws=irfdraws)
  return(relist)

}
