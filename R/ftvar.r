ftvar <- function(mydata,factors,NoFactors=1,NoLags=1,slowindex="",frotvar,thMax=4,thVar=1,RandomWalk=TRUE,Intercept=TRUE,prior=1,priorparam=NULL,Lipr=4,nreps=200,burnin=100,irfhorizon=20,irfquantiles=c(0.05,0.95),bootrep=10,ncrit=0.2,stabletest=TRUE){
  #
  # Preliminaries
  #
  constant <- 0
  if(Intercept==TRUE){
    constant <- 1
  }
  xdata <- as.matrix(factors)
  ydata <- as.matrix(mydata)
  x <- demean(xdata)
  y <- demean(ydata)
  
  T <- nrow(y)
  N <- ncol(x)
  K <- ncol(y)
  P <- K+NoFactors
  
  # normalize data
  x <- scale(x)
  
  #
  # Check if input is correct
  #
  
  #
  # Declare Variables for storage
  #
  startest <- max(thMax,NoLags)
  Alphadraws <- array(0,dim=c(P*NoLags+constant,P,2,nreps-burnin))
  Sigmadraws <- array(0,dim=c(P,P,2,nreps-burnin))
  irfdraws   <- array(0,dim=c(P,P,irfhorizon,2,nreps-burnin))
  Ldraws     <- array(0,dim=c(ncol(y)+ncol(x),P,2,nreps-burnin))
  irfSmalldraws <- array(0,dim=c(P,P,irfhorizon,2,nreps-burnin))
  irfLargedraws  <- array(0,dim=c(P,ncol(y)+ncol(x),irfhorizon,2,nreps-burnin))
  tardraws   <- array(0,dim=c(nreps-burnin))
  deldraws   <- array(0,dim=c(nreps-burnin))
  NoRegimes  <- T-(startest+1)
  regimes    <- array(0,dim=c(NoRegimes,nreps-burnin))
  
  #
  # Extract factors and put it in state-space form
  #
  print("extracting factors")
  fac <- exfact(ydata=y,xdata=x,slowcode=slowindex,NoFactors=NoFactors)
  print("putting it into state-space form")
  XY  <- cbind(y,x)
  FY  <- cbind(fac,y)
  Li  <- olssvd(XY,FY)
  
  res <- XY-FY%*%Li
  Sig <- t(res)%*%res/T
  
  L <- array(0,dim=c(ncol(XY),P,2))
  Sigma <- array(0,dim=c(ncol(XY),ncol(XY),2))
  for(ii in 1:2){
    Sigma[,,ii] <- Sig
	L[,,ii] <- Li
  }
    
  #
  # Set priors
  # 
  
  # Var coefficients
  if(prior==1){
    # Independent Normal-Wishart prior
	if(isempty(priorparam)){
	  stop("No prior parameters for Independent Normal-Wishart prior")
	}
	coefprior    <- priorparam[[1]]
	coefpriorvar <- priorparam[[2]]
	varprior     <- priorparam[[3]]
	varpriordof  <- priorparam[[4]]
	
	pr <- niprior(P,NoLags,RandomWalk=RandomWalk,Intercept=Intercept,coefprior=coefprior,coefpriorvar=coefpriorvar,varprior=varprior)
	
	aprior <- as.vector(pr$coefprior)
	Vprior <- pr$coefpriorvar
	vprior <- varpriordof
	Sprior <- pr$varprior  
  }
  else if(prior==2){
    # Minnesota prior not supported for threshold models
	stop("Minnesota prior not supported for threshold models")
  }
  else if(prior==3){
    # Natural conjugate prior
	
	if(isempty(priorparam)){
	  stop("No prior parameters for Natural conjugate prior")
	}
	coefprior    <- priorparam[[1]]
	coefpriorvar <- priorparam[[2]]
	varprior     <- priorparam[[3]]
	varpriordof  <- priorparam[[4]]
	
	pr <- ncprior(P,NoLags,RandomWalk=RandomWalk,Intercept=Intercept,coefprior=coefprior,coefpriorvar=coefpriorvar,varprior=varprior)
	aprior <- pr$coefprior
	Vprior <- pr$coefpriorvar
	vprior <- varpriordof
	Sprior <- pr$varprior 
  }
  else if(prior==4){
    # Uninformative prior, do nothing
  }
  
  # observation equation
  Liprvar <- Lipr*diag(1,P)
  alpha   <- 0.01
  beta    <- 0.01
  
  #
  # Initialize the Gibbs sampler
  #
  
  thDelay     <- thMax
  tard        <- seq(1:thMax)
  startest    <- max(thMax,NoLags)
  ytest       <- y[(startest+1-thDelay):(T-thDelay),thVar]
  tarmean     <- mean(ytest)
  tarstandard <- sqrt(var(ytest))
  tart        <- tarmean 
  thx         <- thVar+NoFactors
  
  xsplit <- splitVariables(y=FY,lags=NoLags,thDelay=thDelay,thresh=thx,tart=tart,intercept=Intercept)
  
  Beta <- array(0,dim=c(P*NoLags+constant,P,2))
  SF   <- array(0,dim=c(P,P,2))
  
  Beta[,,1] <- solve(t(xsplit$x1)%*%xsplit$x1)%*%t(xsplit$x1)%*%xsplit$y1
  Beta[,,2] <- solve(t(xsplit$x2)%*%xsplit$x2)%*%t(xsplit$x2)%*%xsplit$y2
  
  SF[,,1]   <- t(xsplit$y1-xsplit$x1%*%Beta[,,1])%*%(xsplit$y1-xsplit$x1%*%Beta[,,1])
  SF[,,2]   <- t(xsplit$y2-xsplit$x2%*%Beta[,,2])%*%(xsplit$y2-xsplit$x2%*%Beta[,,2])
  
  
  
  
  #
  # Start MCMC algorithm
  #
  for(irep in 1:nreps){
    print(irep)
  
    # Step 1: split states
	xsplit <- splitVariables(y=FY,lags=NoLags,thDelay=thDelay,thresh=(thVar+NoFactors),tart=tart,intercept=FALSE)
	
	
	# Step 2: Sample L and Sigma for both regimes
	
	# regime 1
	nr <- nrow(XY)
	nr2 <- nrow(as.matrix(xsplit$ytest,ncol=1))

	rdiff <- nr-nr2+1
	XYred <- XY[rdiff:nr,]
	XYsplit <- XYred[xsplit$e1,]
	for(ii in 1:ncol(XYsplit)){
	  if(ii>K){
	    Lipostvar <- solve(solve(Liprvar)+Sigma[ii,ii,1]^(-1)*t(xsplit$y1)%*%xsplit$y1)
		Lipostmean <- Lipostvar%*%(Sigma[ii,ii,1]^(-1)*t(xsplit$y1)%*%XYsplit[,ii])
		L[ii,1:P,1] <- t(Lipostmean)+rnorm(P)%*%chol(Lipostvar)
	  }
	  resi <- XYsplit[,ii]-xsplit$y1%*%L[ii,,1]
	  sh   <- alpha/2+nrow(xsplit$y1)/2
	  sc   <- beta/2+t(resi)%*%resi/2
	  Sigma[ii,ii,1] <- rgamma(1,shape=sh,scale=sc)
	}
	
	# regime 2
	
	XYsplit <- XYred[!xsplit$e1,]
	for(ii in 1:ncol(XYsplit)){
	  if(ii>K){
	    Lipostvar <- solve(solve(Liprvar)+Sigma[ii,ii,2]^(-1)*t(xsplit$y2)%*%xsplit$y2)
		Lipostmean <- Lipostvar%*%(Sigma[ii,ii,1]^(-1)*t(xsplit$y2)%*%XYsplit[,ii])
		L[ii,1:P,2] <- t(Lipostmean)+rnorm(P)%*%chol(Lipostvar)
	  }
	  resi <- XYsplit[,ii]-xsplit$y2%*%L[ii,,1]
	  sh   <- alpha/2+nrow(xsplit$y2)/2
	  sc   <- beta/2+t(resi)%*%resi/2
	  Sigma[ii,ii,2] <- rgamma(1,shape=sh,scale=sc)
	}
	
	# Step 3: sample var coefficients
	
	xsplit <- splitVariables(y=FY,lags=NoLags,thDelay=thDelay,thresh=(thVar+NoFactors),tart=tart,intercept=Intercept)
	if(prior==1){
	  # Independent Normal-Wishart prior
	  # First regime
	  postdraw <- postni(xsplit$y1,xsplit$x1,aprior=aprior,Vprior=Vprior,vprior=vprior,Sprior=Sprior,Sigma=SF[,,1],Intercept=Intercept,stabletest=stabletest,NoLags=NoLags)
	  Beta[,,1] <- postdraw$Alpha
	  SF[,,1]   <- postdraw$Sigma
	  
	  # Second regime
	  postdraw <- postni(xsplit$y2,xsplit$x2,aprior=aprior,Vprior=Vprior,vprior=vprior,Sprior=Sprior,Sigma=SF[,,2],Intercept=Intercept,stabletest=stabletest,NoLags=NoLags)
	  Beta[,,2] <- postdraw$Alpha
	  SF[,,2]   <- postdraw$Sigma
	}
	else if(prior==3){
	  # Natural Conjugate prior 
	  # First regime
	  postdraw <- postnc(xsplit$y1,xsplit$x1,aprior=aprior,Vprior=Vprior
	                     ,vprior=vprior,Sprior=Sprior,Sigma=SF[,,1]
						 ,Intercept=Intercept,stabletest=stabletest
						 ,NoLags=NoLags)
						 
	  Beta[,,1] <- postdraw$Alpha
	  SF[,,1]   <- postdraw$Sigma
	  
	  # Second regime
	  postdraw <- postnc(xsplit$y2,xsplit$x2,aprior=aprior,Vprior=Vprior
	                     ,vprior=vprior,Sprior=Sprior,Sigma=SF[,,2]
						 ,Intercept=Intercept,stabletest=stabletest
						 ,NoLags=NoLags)
						 
	  Beta[,,2] <- postdraw$Alpha
	  SF[,,2]   <- postdraw$Sigma
	
	}
	else if(prior==4){
	  # uninformative prior 
	  # First regime
	  postdraw <- postun(xsplit$y1,xsplit$x1,Sigma=SF[,,1],Intercept=Intercept
	                     ,stabletest=stabletest,NoLags=NoLags)
	  Beta[,,1] <- postdraw$Alpha
	  SF[,,1]   <- postdraw$Sigma
	  
	  # Second regime
	  postdraw <- postun(xsplit$y2,xsplit$x2,Sigma=SF[,,2],Intercept=Intercept
	                     ,stabletest=stabletest,NoLags=NoLags)
	  Beta[,,2] <- postdraw$Alpha
	  SF[,,2]   <- postdraw$Sigma
	}
	
	# Step 4: sample new threshold
	tarnew <- tart+rnorm(1,sd=tarstandard)
	l1post <- tarpost(xsplit$xstar,xsplit$ystar,Ytest=ytest,Beta[,,1],Beta[,,2]
	                  ,SF[,,1],SF[,,2],tarnew,NoLags,intercept=Intercept
					  ,tarmean,tarstandard,ncrit=ncrit)
					  
	l2post <- tarpost(xsplit$xstar,xsplit$ystar,Ytest=ytest,Beta[,,1],Beta[,,2]
	                  ,SF[,,1],SF[,,2],tart,NoLags,intercept=Intercept
					  ,tarmean,tarstandard,ncrit=ncrit)
	
	acc <- min(1,exp(l1post$post-l2post$post))
	u <- runif(1)
	if(u<acc){
	  tart=tarnew
	}
	#tarmean=tart
	
	
	# Step 5: Sample new delay parameter
	prob <- matrix(0,nrow=thMax)
	for(jj in 1:thMax){
	  split1 <- splitVariables(y=FY,lags=NoLags,jj,thVar+NoFactors,tart,intercept=Intercept)
	  x <- exptarpost(split1$xstar,split1$ystar,split1$ytest,Beta[,,1],Beta[,,2],SF[,,1],SF[,,2],tart,NoLags,intercept=Intercept,tarmean,tarstandard,ncrit=ncrit)
	  prob[jj,1] <- x$post
	}
	#print(prob)
	mprob <- max(prob)
	prob <- exp(prob-mprob)
	prob <- prob/sum(prob)
	#print(prob)
	#readline(prompt="Press [enter] to continue")
	#prob <- prob/sum(prob)
	if(anyNA(prob)){
	  prob <- matrix(1/thMax,nrow=thMax)
	}
	thDelay <- sample(thMax,1,replace=FALSE,prob)
	
	# Store results after burnin-period
	if(irep>burnin){
	  # Store draws for Beta and Sigma and L
	  Sigmadraws[,,,irep-burnin] <- SF
	  Alphadraws[,,,irep-burnin] <- Beta 
	  Ldraws[,,,irep-burnin] <- L
	  
	  tardraws[irep-burnin] <- tart
	  deldraws[irep-burnin] <- thDelay
	  
	  # Regimes
      nT <- length(xsplit$e1)
      a  <- nT-NoRegimes
      regimes[,irep-burnin] <- xsplit$e1[(1+a):nT]
		
	  # Compute Impulse-Response functions
	  for(ii in 1:P){
        xx <- tirf(xsplit$ystar,xsplit$ytest,Beta[,,1],Beta[,,2]
		           ,SF[,,1],SF[,,2],tart,thVar,thDelay,NoLags
				   ,irfhorizon,Intercept=Intercept,shockvar=ii
				   ,bootrep=bootrep)
				   
        #print(dim(xx$irf1))
        irfSmalldraws[ii,,,1,irep-burnin]<-xx$irf1
        irfSmalldraws[ii,,,2,irep-burnin]<-xx$irf2
		
      }
	  for(ii in 1:P){
          irfLargedraws[ii,,,1,irep-burnin] <- L[,,1]%*%irfSmalldraws[ii,,,1,irep-burnin]
		  irfLargedraws[ii,,,2,irep-burnin] <- L[,,2]%*%irfSmalldraws[ii,,,1,irep-burnin]
      }

	
	} # end storing results
	
  } # End loop over mcmc algorithm
	
  # Prepare return values
  irfSmallFinal <- array(0,dim=c(P,P,irfhorizon,2,3))
  irfLargeFinal <- array(0,dim=c(P,(ncol(XY)),irfhorizon,2,3))
  irflower <- min(irfquantiles)
  irfupper <- max(irfquantiles)
  for(jj in 1:P){
    for(kk in 1:P){
      for(ll in 1:irfhorizon){
	    # Regime 1
        irfSmallFinal[jj,kk,ll,1,1] <- mean(irfSmalldraws[jj,kk,ll,1,])
        irfSmallFinal[jj,kk,ll,1,2] <- quantile(irfSmalldraws[jj,kk,ll,1,],probs=irflower)
        irfSmallFinal[jj,kk,ll,1,3] <- quantile(irfSmalldraws[jj,kk,ll,1,],probs=irfupper)
		# Regime 2
		irfSmallFinal[jj,kk,ll,2,1] <- mean(irfSmalldraws[jj,kk,ll,2,])
        irfSmallFinal[jj,kk,ll,2,2] <- quantile(irfSmalldraws[jj,kk,ll,2,],probs=irflower)
        irfSmallFinal[jj,kk,ll,2,3] <- quantile(irfSmalldraws[jj,kk,ll,2,],probs=irfupper)
      }
    }
  }
  for(jj in 1:P){
    for(kk in 1:(ncol(XY))){
	  for(ll in 1:irfhorizon){
	    # Regime 1
		irfLargeFinal[jj,kk,ll,1,1] <- mean(irfLargedraws[jj,kk,ll,1,])
		irfLargeFinal[jj,kk,ll,1,2] <- quantile(irfLargedraws[jj,kk,ll,1,],probs=irflower)
		irfLargeFinal[jj,kk,ll,1,3] <- quantile(irfLargedraws[jj,kk,ll,1,],probs=irfupper)
		
		# Regime 2
		irfLargeFinal[jj,kk,ll,2,1] <- mean(irfLargedraws[jj,kk,ll,2,])
		irfLargeFinal[jj,kk,ll,2,2] <- quantile(irfLargedraws[jj,kk,ll,2,],probs=irflower)
		irfLargeFinal[jj,kk,ll,2,3] <- quantile(irfLargedraws[jj,kk,ll,2,],probs=irfupper)
	  }
	}
  }
	retlist <- list(Betadraws=Alphadraws,Sigmadraws=Sigmadraws,Ldraws=Ldraws,irfSmall=irfSmallFinal,irfLarge=irfLargeFinal,deldraws=deldraws,regimes=regimes,tardraws=tardraws)
	
	return(retlist)
	
  
}